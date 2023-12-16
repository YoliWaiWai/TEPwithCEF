clear all
close all
clc
D=runpf('case6ww');
mpc=case6ww;
I = mpc.branch(:,1);
J = mpc.branch(:,2);
In = myincidence(I,J); 
G = digraph(I,J);
figure;
h = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);

%% ***********Parameters **********
N=6; % number of load nodes
L=11; % number of lines
Sbase=mpc.baseMVA;  % unit:VA
d = mpc.bus(:,3)/Sbase;
g_N_thermal = mpc.gen(:,9)/Sbase; %火电机组容量
p_max = 1.5;%线路传输功率上限
M = 1e5;

%% Nodal Y Matrix→B matrix
Y=makeYbus(D); %节点导纳矩阵
X=mpc.branch(:,4);

%% ***********Variable statement**********
theta = sdpvar(N,1);
p = sdpvar(L,1);
x = binvar(L,1);
g = sdpvar(N,1);

%% ***********Constraints*************
Obj = sum(x);
Cons = [];

%直流潮流约束+TEP
Cons_DC=[];
Cons_DC=[
    % In*p==g-d,In'*theta==p.*X,theta(1)==0
    -(1-x)*M <= In'*theta - p.* X <= (1-x)*M,
    In*p==g-d;
    theta(1)==0,
    -x.*p_max <= p <=x.*p_max;
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
s_theta = value(theta)
s_g = value(g)
h.EdgeLabel = s_p;
h.NodeLabel = s_g;
title('规划结果');

