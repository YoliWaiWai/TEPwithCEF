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
N=6; % number of load nodes
L=11; % number of all lines
K=4; % number of coal generation types
Sbase=mpc.baseMVA;  % unit:VA
pd = mpc.bus(:,PD)/Sbase; %负荷需求标幺值
g_max = mpc.gen(:,PMAX)/Sbase; %火电机组容量
g_max_all=[0.6,1.2,2,2.4];
p_max = mpc.branch(:,RATE_A)/Sbase; %线路传输功率上限
xb = mpc.branch(:,BR_X); %线路电抗
c_lines = xb*100;  %用线路电抗代表线路长度，得到线路建设成本c_lines
c_gen = [13,22,37.5,45];

I = mpc.branch(:,F_BUS);
J = mpc.branch(:,T_BUS);
[Ainc] = makeIncidence(mpc); % branch-node incidence matrix
In=Ainc'; % node-branch incidence matrix, but with all lines closed
% In = myincidence(I,J); 
l_status = zeros(1, L);
l_E = [2,3,6,8,9]; % 已建设线路
l_c = setdiff([1:L],l_E); %待建设线路选项
l_status(l_E)= 1;

%% 计算当前线路连接状态下的潮流并画图
mpc.branch(:, 11) = l_status;
result = runpf(mpc);

% 潮流结果
fprintf('线路潮流:\n');
disp(result.branch(:, [1, 2, 14]));

%% 计算碳排放流
P_B=zeros(N);  %
P_B_IJ = result.branch(:,14);
for l=1:size(In,1)
    if P_B_IJ(l)>0
        P_B(I(l),J(l))=P_B_IJ(l);
    else
        P_B(I(l),J(l))=-P_B_IJ(l);
    end
end
P_G=zeros(3,N); % 
for k=1:3
    n=result.gen(k,GEN_BUS);
    P_G(k,n)=result.gen(k,PG);
end
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
M = 1e5;

%% Nodal Y Matrix→B matrix
Y=makeYbus(D); %节点导纳矩阵

%% ***********Variable statement**********
theta = sdpvar(N,1);
p = sdpvar(L,1);
pd_shed = sdpvar(N,1);
x_lines = binvar(L,1);
x_gen_coal = binvar(3,K);
x_gen_gas = binvar(3,5);
x_gen_pws = binvar(3,2);
x_gen_nuc = binvar(3,1);
g = sdpvar(N,4);

%% ***********Constraints*************
c2=mpc.gencost(:,5); %发电成本函数二次项系数
c2_all=[c2;0.0063]';
c1=mpc.gencost(:,6); %发电成本函数一次项系数
c1_all=[c1;10.93]';
Obj_inv = sum(c_lines.*(x_lines-l_status'))+sum(c_gen.*sum(x_gen_coal,1));
Obj_ope=M*sum(pd_shed);
for i=1:3
    Obj_ope= Obj_ope+sum(c2_all.*g(i,:).*2+c1_all.*g(i,:));
end
Obj=Obj_inv+Obj_ope;

Cons = [];
%已建设线路
Cons=[x_lines(l_E)==1];
%% Cons1: 直流潮流约束+TEP
Cons_DC=[];
Cons_DC=[
    % In*p==g-d,In'*theta==p.*X,theta(1)==0
    -(1-x_lines)*M <= In'*theta - p.* xb <= (1-x_lines)*M,
    In*p==sum(g,2)-(pd-pd_shed);
    theta(1)==0,
    -x_lines.*p_max <= p <=x_lines.*p_max;
    pd_shed>=0;
];

Cons=[Cons, Cons_DC];

%% Cons2: 机组发电功率约束
for i=1:3
    Cons=[Cons, sum(x_gen_coal(i,:))==1];
    for k=1:K
        Cons=[Cons, 0 <= g(i,k) <= x_gen_coal(i,k).*g_max_all(k)];
    end
end
Cons=[Cons, g(4:6,:) == 0];

%% Solve the TEP problem
ops=sdpsettings('verbose',2,'solver','gurobi');
sol = optimize(Cons,Obj,ops);

%% 绘图
s_x_lines = value(x_lines)
s_x_gen_coal = value(x_gen_coal)
s_p = value(p)
s_pd_shed = value(pd_shed)
s_theta = value(theta)
s_g = value(g)
figure
h2 = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);
h2.EdgeLabel = s_p;
l_new=setdiff(find(round(s_x_lines)==1),l_E); %新建的线路
highlight(h2,I(l_E),J(l_E),'LineWidth',3,'EdgeColor','k'); %已建设线路
highlight(h2,I(find(round(s_x_lines)==0)),J(find(round(s_x_lines)==0)),'LineStyle','--','LineWidth',1,'EdgeColor','b'); %未建设线路
highlight(h2,I(l_new),J(l_new),'LineStyle','--','LineWidth',3,'EdgeColor','g'); %新建设线路
% h.NodeLabel = s_g;
title('规划结果');

% 在节点上标记发电机选型、发电机出力信息
for i = 1:3
    label_str = sprintf('机组出力：%.2f',sum(s_g(i,:)));    
    text(h2.XData(i)+0.2, h2.YData(i)-0.1, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
    label_str = sprintf('机组选型：%.1f',find(s_x_gen_coal(i,:)));    
    text(h2.XData(i)+0.2, h2.YData(i)+0.1, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
end
