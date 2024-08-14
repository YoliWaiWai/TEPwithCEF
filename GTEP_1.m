%% 一个简单的输电网扩展规划算例示意
% 基于matpower中的6节点网络，case6ww.m。
clear all
close all
clc
define_constants; %打开这个函数可明确mpc的各个矩阵包含的信息，同时参见[1]
% [1]Appendix B Data File Format, MATPWER User s Manual Version 7.1
D=runpf('case6ww');
mpc=case6ww;

%% ***********Parameters **********
T = 24; 
N = 6; % number of load nodes
L = 11; % number of all lines
K = 4; % number of coal generation types
Sbase = mpc.baseMVA;  % unit:VA

g_max = mpc.gen(:,PMAX)/Sbase; %火电机组容量
g_max_all = [0.6,1.2,2,2.4];
g_min_all = [0.1,0.1,0.1,0.1];
p_max = mpc.branch(:,RATE_A)/Sbase; %线路传输功率上限
xb = mpc.branch(:,BR_X); %线路电抗
c_lines = xb*100;  %用线路电抗代表线路长度，得到线路建设成本c_lines
%c_gen = [12.9,22,37.5,45];%四种不同类型的燃煤机组静态投资成本/亿元
c0 = mpc.gencost(:,7); %发电成本函数零次项系数
c_gen = [c0;280]';
I = mpc.branch(:,F_BUS);
J = mpc.branch(:,T_BUS);
[Ainc] = makeIncidence(mpc); % branch-node incidence matrix
In=Ainc'; % node-branch incidence matrix, but with all lines closed 
%sum_N_g = zeros(N, T);
Cu_NL = [2 3 4 5]; % No-load cost of unit
Cup = [5 10 5 5]; % Startup cost of unit
Cdown = [5 10 5 5]; % Shutdown cost of unit
% Adding minimum up- and down-time
TUg = [6;15;1;1];  %minup
TDg = [3;6;3;3];   %mindown
%生成一组24h负荷需求数据
pd = mpc.bus(:,PD)/Sbase; %负荷需求标幺值
System_demand = xlsread('dataset',2,'B70:B93')/1000;
P_load = (System_demand/3 .* pd')';%6*24

%% 设置一个Original scene，计算潮流和发电成本
% 假设原有节点1的机组和5、6节点负荷
gen_status = [1,0,0];
l_status = zeros(1, L);
l_E = [2,3]; % 已建设线路
l_c = setdiff([1:L],l_E); %待建设线路选项
l_status(l_E)= 1;
% 计算当前线路连接状态下的潮流并画图
mpc.gen(:, 8) = gen_status;
mpc.branch(:, 11) = l_status;
result = runpf(mpc);
% 潮流结果
fprintf('线路潮流:\n');
disp(result.branch(:, [1, 2, 14]));

%% 绘图
G = digraph(I,J);
figure;
h = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);
h.EdgeLabel = result.branch(:, 14)/Sbase;
highlight(h,I(l_E),J(l_E),'LineWidth',3,'EdgeColor','k'); %画出已建设线路
highlight(h,I(l_c),J(l_c),'LineStyle','-.','LineWidth',1,'EdgeColor','b'); %画出待建设线路选项
title('初始线路');

% 在节点上标记发电机出力信息
for i = 1:3
    label_str = sprintf('机组出力：%.2f', result.gen(i, 2)/Sbase);    
    text(h.XData(i)+0.2, h.YData(i)-0.1, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
end
for i= 4:6
    label_str = sprintf('负荷需求：%.2f',pd(i)); 
    text(h.XData(i)-0.4, h.YData(i)+0.2, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
end
M = 1e5;

%% Nodal Y Matrix→B matrix
Y=makeYbus(D); %节点导纳矩阵

%% ***********Variable statement**********
%投资决策变量
x_lines = binvar(L,1);%在节点N是否建设k型机组
x_gen_coal = binvar(3,K);%在节点N是否建设k型机组
%运行决策变量
theta = sdpvar(N,T);
p = sdpvar(L,T);
pd_shed = sdpvar(N,T);
g_exist = sdpvar(N,T);
sum_N_g = sdpvar(N,1,T);
u = binvar(3,K,T,'full');%节点N的第K台机组在t时段是否运行
v = binvar(3,K,T,'full');%节点N的第K台机组在t时刻是否开启
w = binvar(3,K,T,'full');%节点N的第K台机组在t时刻是否关停
g = sdpvar(N,K,T,'full');%节点N的第K台机组在t时段的输出功率
%x_gen_gas = binvar(3,5);
%x_gen_pws = binvar(3,2);
%x_gen_nuc = binvar(3,1);


%% ***********Constraints*************
Cons = [];
%已建设线路
Cons=[x_lines(l_E)==1];

c2=mpc.gencost(:,5); %发电成本函数二次项系数
c2_all=[c2;0.0063]';
%c2_all=[0;0;0;0]';
c1=mpc.gencost(:,6); %发电成本函数一次项系数
c1_all=[c1;10.93]';
%c0=mpc.gencost(:,7); %发电成本函数零次项系数(投资成本）
%c0_all=[c1;0]';
Obj_inv = sum(c_lines.*(x_lines))+sum(c_gen.*sum(x_gen_coal,1));%
Obj = 0;
Obj_u = 0;
Obj_up = 0;
Obj_down = 0;
for t = 1:T
    Obj_ope = M*sum(pd_shed(:,t))+sum(c2.*g_exist(1:3,t).^2+c1.*g_exist(1:3,t));%原有机组发电成本
    %新增机组发电成本
    for i=1:3
    Obj_ope= Obj_ope+sum(c2_all.*g(i,:,t).^2 + c1_all.*g(i,:,t));
    Obj_u=Obj_u+sum(Cu_NL.*u(i,:,t));
    Obj_up=Obj_up+sum(Cup.*v(i,:,t));
    Obj_down=Obj_down+sum(Cdown.*w(i,:,t));
    end
Obj = Obj+Obj_inv+Obj_ope+Obj_u+Obj_up+Obj_down;
%% Cons1: 直流潮流约束+TEP

Cons_DC=[Cons,-(1 - x_lines)*M <= In'*theta(:,t) - p(:,t).* xb];
Cons_DC=[Cons_DC,In'*theta(:,t) - p(:,t).* xb <= (1 - x_lines)*M];
Cons_DC=[Cons_DC,sum_N_g == sum(g,2)];
Cons_DC=[Cons_DC,In*p(:,t) == sum_N_g(:,:,t)+g_exist(:,t)-(P_load(:,t)-pd_shed(:,t)) ];  
Cons_DC=[Cons_DC,theta(1,t)==0];  
Cons_DC=[Cons_DC,- x_lines .* p_max <= p(:,t)];  
Cons_DC=[Cons_DC,p(:,t) <= x_lines .* p_max];  

Cons_DC=[Cons_DC,pd_shed(:,t)>=0];

Cons=[Cons_DC];
%% Cons2: 机组发电功率约束
% 原有机组
Cons=[Cons, g_exist((2:6),t)==0];
Cons=[Cons,0 <= g_exist(1,t); g_exist(1,t)<= g_max(1)];
% 新增机组
for i=1:3
   % Cons=[Cons, sum(x_gen_coal(i,:))<=1];%每个节点最多建设一种
    for k=1:K
        Cons = [Cons, u(i,k,t) <= x_gen_coal(i,k)];%运行的机组和投建机组的关系
        Cons=[Cons, u(i,k,t)*x_gen_coal(i,k).*g_min_all(k) <= g(i,k,t) <= u(i,k,t)*x_gen_coal(i,k).*g_max_all(k)];%机组发电功率上限
    end
end
Cons=[Cons, g((4:6),:,t) == 0];
end
%% Cons3: 机组启停时间约束
for k=1:K
    for n = 1:3
        for t = TUg(k):T
        Cons = [Cons,sum(v(n,k,(t-TUg(k)+1):t),3)<=u(n,k,t)];
        end
        for t=TDg(k):T
        Cons = [Cons,sum(w(n,k,(t-TDg(k)+1):t),3)<=1-u(n,k,t)];
        end
    end
end
for t = 2:T
    Cons = [Cons,u(:,:,t)-u(:,:,t-1) == v(:,:,t)-w(:,:,t)];
end

for t = 1:T
    for n = 1:3
        Cons = [Cons, sum(g(n,:,t)) >= P_load(n,t)];
        Cons = [Cons, sum(u(n,:,t).*g_max_all) >= P_load(n,t)];
    end
end
%% Solve the TEP problem
ops=sdpsettings('verbose',2,'solver','gurobi');
sol = optimize(Cons,Obj,ops);

%% 绘图
s_x_lines = value(x_lines);
s_x_gen_coal = value(x_gen_coal);
s_p = value(p);
s_pd_shed = value(pd_shed);
s_theta = value(theta);
s_g = value(g);
s_u = value(u);
s_v = value(v);
s_w = value(w);
s_g_exist = value(g_exist) ;
figure
h2 = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);
l_new=setdiff(find(round(s_x_lines)==1),l_E); %新建的线路
highlight(h2,I(l_E),J(l_E),'LineWidth',3,'EdgeColor','k'); %已建设线路
highlight(h2,I(find(round(s_x_lines)==0)),J(find(round(s_x_lines)==0)),'LineStyle','--','LineWidth',1,'EdgeColor','b'); %未建设线路
highlight(h2,I(l_new),J(l_new),'LineStyle','--','LineWidth',3,'EdgeColor','g'); %新建设线路
title('规划结果');

for t = 1:T
    Obj_ope = M*sum(pd_shed(:,t))+sum(c2.*g_exist(1:3,t).*2+c1.*g_exist(1:3,t));%原有机组发电成本
    %新增机组发电成本
    for i=1:3
    Obj_ope= Obj_ope+sum(c2_all.*g(i,:,t).*2+c1_all.*g(i,:,t));
    Obj_u=Obj_u+sum(Cu_NL.*u(i,:,t));
    Obj_up=Obj_up+sum(Cup.*v(i,:,t));
    Obj_down=Obj_down+sum(Cdown.*w(i,:,t));
    end
fprintf('时段 %d 运行成本: %.2f\n', t, value(Obj_ope)); 

end
% 在节点上标记发电机选型、发电机出力信息
for i = 1:3
    if any(s_x_gen_coal(i, :) ~= 0)
        label_str = sprintf('机组选型：%d',find(s_x_gen_coal(i,:)));    
        text(h2.XData(i)+0.2, h2.YData(i)+0.1, label_str, ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
        label_str = sprintf('机组出力：%.2f',sum(s_g(i,:)));    
        text(h2.XData(i)+0.2, h2.YData(i)-0.1, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
    else
        % 没有建设新机组的情况
        label_str = '未建设新机组';  
        text(h2.XData(i) + 0.2, h2.YData(i) + 0.1, label_str, ...
            'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
    end
end
