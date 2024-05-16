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
Hours = 24; 
N = 6; % number of load nodes
L = 11; % number of all lines
K = 4; % number of coal generation types
Sbase = mpc.baseMVA;  % unit:VA
g_max_all = [30,60,100,120]/Sbase;
g_min_all = [0.7,0.7,0.55,0.55] .* g_max_all;
x_coal_max = [4,14,1,3];
p_max = mpc.branch(:,RATE_A)/Sbase; %线路传输功率上限
xb = mpc.branch(:,BR_X); %线路电抗
c_lines = xb*100;  %用线路电抗代表线路长度，得到线路建设成本c_lines
c2 = mpc.gencost(:,5); %发电成本函数二次项系数
c2_all = [c2;0.0063]';
%c2_all=[0;0;0;0]';
c1=mpc.gencost(:,6); %发电成本函数一次项系数
c1_all=[c1;10.93]';
%c0_all=[c1;0]';
%c_gen = [12.9,22,37.5,45];%四种不同类型的燃煤机组静态投资成本/亿元
c0 = mpc.gencost(:,7); %发电成本函数零次项系数(投资成本）
c_gen = [c0;280];
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
x_lines = binvar(L,1);%是否建设线路L
x_gen_coal_1 = binvar(3,x_coal_max(1));%在3个节点各建设几台1型燃煤机组
x_gen_coal_2 = binvar(3,x_coal_max(2));%在3个节点各建设几台2型燃煤机组
x_gen_coal_3 = binvar(3,x_coal_max(3));%在3个节点各建设几台3型燃煤机组
x_gen_coal_4 = binvar(3,x_coal_max(4));%在3个节点各建设几台4型燃煤机组
x_gens = binvar(4,1);%
%运行决策变量
theta = sdpvar(N,Hours);
p = sdpvar(L,Hours);
pd_shed = sdpvar(N,Hours);
g_exist = sdpvar(N,Hours);
u = binvar(3,K,Hours,'full');%节点N的第K台机组在t时段是否运行
v = binvar(3,K,Hours,'full');%节点N的第K台机组在t时刻是否开启
w = binvar(3,K,Hours,'full');%节点N的第K台机组在t时刻是否关停
g_coal_1 = sdpvar(N,x_coal_max(1),Hours,'full');%节点N的第K台机组在t时段的输出功率
g_coal_2 = sdpvar(N,x_coal_max(2),Hours,'full');
g_coal_3 = sdpvar(N,x_coal_max(3),Hours,'full');
g_coal_4 = sdpvar(N,x_coal_max(4),Hours,'full');
sum_N_g = sdpvar(N,1,Hours);%6个节点的机组输出功率
sum_type_g = sdpvar(N,length(x_coal_max),Hours,'full');%四种类型一共发了多少
%x_gen_gas = binvar(3,5);
%x_gen_pws = binvar(3,2);
%x_gen_nuc = binvar(3,1);

%% ***********Constraints*************
%建设成本
Cons = [];
Cons = [Cons,x_gens(1) == sum(sum(x_gen_coal_1))];
Cons = [Cons,x_gens(2) == sum(sum(x_gen_coal_2))];
Cons = [Cons,x_gens(3) == sum(sum(x_gen_coal_3))];
Cons = [Cons,x_gens(4) == sum(sum(x_gen_coal_4))];
Obj_inv = sum(c_lines.*(x_lines))+sum(c_gen .* x_gens);
%发电成本
Obj = 0;
Obj_u = 0;
Obj_up = 0;
Obj_down = 0;
Cons = [Cons,sum_type_g(:,1,:) == sum(g_coal_1,2)]; 
Cons = [Cons,sum_type_g(:,2,:) == sum(g_coal_2,2)];
Cons = [Cons,sum_type_g(:,3,:) == sum(g_coal_3,2)];
Cons = [Cons,sum_type_g(:,4,:) == sum(g_coal_4,2)];
for t = 1:Hours
    Obj_ope = M * sum(pd_shed(:,t)) + sum(c2.*g_exist(1:3,t).^2 + c1.*g_exist(1:3,t));%原有机组发电成本
    %新增机组发电成本
    for i = 1:N 
    Obj_ope = Obj_ope + sum(c2_all.*sum_type_g(i,:,t).^2 + c1_all.*sum_type_g(i,:,t));
    %Obj_u = Obj_u + sum(Cu_NL.*u(i,:,t));机组组合部分未改
    %Obj_up = Obj_up + sum(Cup.*v(i,:,t));
    %Obj_down = Obj_down + sum(Cdown.*w(i,:,t));
    end
Obj = Obj + Obj_inv + Obj_ope + Obj_u + Obj_up + Obj_down;
%% Cons1: 直流潮流约束+TEP
Cons=[Cons,x_lines(l_E) == 1];%已建设线路
Cons_DC=[Cons,-(1 - x_lines)*M <= In'*theta(:,t) - p(:,t).* xb];
Cons_DC=[Cons_DC,In'*theta(:,t) - p(:,t).* xb <= (1 - x_lines) * M];
Cons_DC=[Cons_DC,sum_N_g == sum(g_coal_1,2) + sum(g_coal_2,2) + sum(g_coal_3,2) + sum(g_coal_4,2)];
Cons_DC=[Cons_DC,In * p(:,t) == sum_N_g(:,:,t) + g_exist(:,t) - (P_load(:,t) - pd_shed(:,t)) ];  
Cons_DC=[Cons_DC,theta(1,t) == 0];  
Cons_DC=[Cons_DC,- x_lines .* p_max <= p(:,t)];  
Cons_DC=[Cons_DC,p(:,t) <= x_lines .* p_max];  
Cons_DC=[Cons_DC,pd_shed(:,t) >= 0];
Cons=[Cons_DC];
%% Cons2: 机组发电功率约束
% 原有机组
Cons=[Cons, g_exist((2:6),t) == 0];%初始条件：节点1有一台机组
Cons=[Cons,g_min_all(1) <= g_exist(1,t); g_exist(1,t)<= g_max_all(1)];
% 新增机组
for i=1:3
        %Cons = [Cons, u(i,k,t) <= x_gen_coal(i,k)];%运行的机组和投建机组的关系
        Cons=[Cons, x_gen_coal_1(i,:).*g_min_all(1) <= g_coal_1(i,:,t) <= x_gen_coal_1(i,:).*g_max_all(1)];%机组发电功率上限
        Cons=[Cons, x_gen_coal_2(i,:).*g_min_all(2) <= g_coal_2(i,:,t) <= x_gen_coal_2(i,:).*g_max_all(2)];
        Cons=[Cons, x_gen_coal_3(i,:).*g_min_all(3) <= g_coal_3(i,:,t) <= x_gen_coal_3(i,:).*g_max_all(3)];
        Cons=[Cons, x_gen_coal_4(i,:).*g_min_all(4) <= g_coal_4(i,:,t) <= x_gen_coal_4(i,:).*g_max_all(4)];
end
% 只有前三个节点可以建设机组
Cons=[Cons, g_coal_1((4:6),:,t) == 0];
Cons=[Cons, g_coal_2((4:6),:,t) == 0];
Cons=[Cons, g_coal_3((4:6),:,t) == 0];
Cons=[Cons, g_coal_4((4:6),:,t) == 0];

end
%% Cons3: 机组启停时间约束
for k=1:K
    for n = 1:3
        for t = TUg(k):Hours
        Cons = [Cons,sum(v(n,k,(t-TUg(k)+1):t),3)<=u(n,k,t)];
        end
        for t=TDg(k):Hours
        Cons = [Cons,sum(w(n,k,(t-TDg(k)+1):t),3)<=1-u(n,k,t)];
        end
    end
end
for t = 2:Hours
    Cons = [Cons,u(:,:,t)-u(:,:,t-1) == v(:,:,t)-w(:,:,t)];
end

for t = 1:Hours
    for n = 1:3
        Cons = [Cons, sum_N_g(n,:,t) >= P_load(n,t)];
        %Cons = [Cons, sum(u(n,:,t).*g_max_all) >= P_load(n,t)];
    end
end
%% Solve the TEP problem
ops=sdpsettings('verbose',2,'solver','gurobi');
sol = optimize(Cons,Obj,ops);

%% 绘图
s_x_lines = value(x_lines);
s_x_gen_coal_1 = value(x_gen_coal_1);
s_x_gen_coal_2 = value(x_gen_coal_2);
s_x_gen_coal_3 = value(x_gen_coal_3);
s_x_gen_coal_4 = value(x_gen_coal_4);
s_p = value(p);
s_pd_shed = value(pd_shed);
s_theta = value(theta);
s_g_coal_1 = value(g_coal_1);
s_g_coal_2 = value(g_coal_2);
s_g_coal_3 = value(g_coal_3);
s_g_coal_4 = value(g_coal_4);
s_sum_N_g = value(sum_N_g);
s_sum_type_g = value(sum_type_g);
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

for t = 1:Hours
    Obj_ope = M*sum(pd_shed(:,t))+sum(c2.*g_exist(1:3,t).*2+c1.*g_exist(1:3,t));%原有机组发电成本
    %新增机组发电成本
    for i=1:3
    Obj_ope= Obj_ope+sum(c2_all .* sum_type_g(i,:,t).*2+c1_all .* sum_type_g(i,:,t));
    Obj_u=Obj_u+sum(Cu_NL.*u(i,:,t));
    Obj_up=Obj_up+sum(Cup.*v(i,:,t));
    Obj_down=Obj_down+sum(Cdown.*w(i,:,t));
    end
fprintf('时段 %d 运行成本: %.2f\n', t, value(Obj_ope)); 
end
