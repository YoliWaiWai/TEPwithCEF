clear all
close all
clc
D=runpf('case6ww');
mpc=case6ww;



%% ***********Parameters **********
N=6; % number of load nodes
L=11; % number of all lines
Sbase=mpc.baseMVA;  % unit:VA
pd = mpc.bus(:,3)/Sbase;
g_N_thermal = mpc.gen(:,9)/Sbase; %火电机组容量
p_max = 1.5;%线路传输功率上限
X = mpc.branch(:,4);
c_lines = X*100; %用线路电抗代表线路长度，得到线路建设成本

I = mpc.branch(:,1);
J = mpc.branch(:,2);
In = myincidence(I,J); 
l_E=[1,2,4,6,9]; % 已建设线路
l_c=setdiff([1:L],l_E);
G = digraph(I,J);
figure;
h = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);
highlight(h,I(l_E),J(l_E),'LineWidth',3,'EdgeColor','k');
highlight(h,I(l_c),J(l_c),'LineStyle','-.','LineWidth',1,'EdgeColor','b');

M = 1e5;

%% Nodal Y Matrix→B matrix
Y=makeYbus(D); %节点导纳矩阵

%% ***********Variable statement**********
theta = sdpvar(N,1);
p = sdpvar(L,1);
pd_shed = sdpvar(N,1);
x = binvar(L,1);
g = sdpvar(N,1);

%% ***********Constraints*************
c2=mpc.gencost(:,5);
c1=mpc.gencost(:,6);
Obj = sum(c_lines.*x)+sum(c2.*g(1:3).*2+c1.*g(1:3))+M*sum(pd_shed);
Cons = [];

%已建设线路
Cons=[x(l_E)==1];

%直流潮流约束+TEP
Cons_DC=[];
Cons_DC=[
    % In*p==g-d,In'*theta==p.*X,theta(1)==0
    -(1-x)*M <= In'*theta - p.* X <= (1-x)*M,
    In*p==g-(pd-pd_shed);
    theta(2)==0,
    -x.*p_max <= p <=x.*p_max;
    pd_shed>=0;
];

Cons=[Cons, Cons_DC];

%机组发电功率约束
Cons=[Cons, 0 <= g(1:3,:) <= g_N_thermal, g(4:6,:) == 0];

%% Solve the TEP problem
ops=sdpsettings('verbose',2,'solver','gurobi');
sol = optimize(Cons,Obj,ops);

%% 绘图
s_x = value(x)
s_p = value(p)
s_pd_shed = value(pd_shed)
s_theta = value(theta)
s_g = value(g)
figure
h2 = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);
h2.EdgeLabel = s_p;
highlight(h2,I(find(round(s_x)==1)),J(find(round(s_x)==1)),'LineWidth',3,'EdgeColor','k');
highlight(h2,I(find(round(s_x)==0)),J(find(round(s_x)==0)),'LineStyle','--','LineWidth',1,'EdgeColor','b');
% h.NodeLabel = s_g;
title('规划结果');

