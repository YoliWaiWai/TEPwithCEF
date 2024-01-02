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
Sbase=mpc.baseMVA;  % unit:VA
pd = mpc.bus(:,PD)/Sbase; %负荷需求标幺值
g_max = mpc.gen(:,PMAX)/Sbase; %火电机组容量
p_max = mpc.branch(:,RATE_A)/Sbase; %线路传输功率上限
xb = mpc.branch(:,BR_X); %线路电抗
c_lines = xb*100;  %用线路电抗代表线路长度，得到线路建设成本c_lines

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
% 绘图
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
x = binvar(L,1);
g = sdpvar(N,1);

%% ***********Constraints*************
c2=mpc.gencost(:,5); %发电成本函数二次项系数
c1=mpc.gencost(:,6); %发电成本函数一次项系数
Obj = sum(c_lines.*x)+sum(c2.*g(1:3).*2+c1.*g(1:3))+M*sum(pd_shed);
Cons = [];

%已建设线路
Cons=[x(l_E)==1];

%直流潮流约束+TEP
Cons_DC=[];
Cons_DC=[
    % In*p==g-d,In'*theta==p.*X,theta(1)==0
    -(1-x)*M <= In'*theta - p.* xb <= (1-x)*M,
    In*p==g-(pd-pd_shed);
    theta(1)==0,
    -x.*p_max <= p <=x.*p_max;
    pd_shed>=0;
];

Cons=[Cons, Cons_DC];

%机组发电功率约束
Cons=[Cons, 0 <= g(1:3,:) <= g_max, g(4:6,:) == 0];

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
l_new=setdiff(find(round(s_x)==1),l_E); %新建的线路
highlight(h2,I(l_E),J(l_E),'LineWidth',3,'EdgeColor','k'); %已建设线路
highlight(h2,I(find(round(s_x)==0)),J(find(round(s_x)==0)),'LineStyle','--','LineWidth',1,'EdgeColor','b'); %未建设线路
highlight(h2,I(l_new),J(l_new),'LineStyle','--','LineWidth',3,'EdgeColor','g'); %新建设线路
% h.NodeLabel = s_g;
title('规划结果');


% 在节点上标记发电机出力信息
for i = 1:3
    label_str = sprintf('机组出力：%.2f',s_g(i));    
    text(h2.XData(i)+0.2, h2.YData(i)-0.1, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
end
