%% 一个简单的输电网扩展规划算例示意
% 基于matpower中的30节点网络，case30.m
clear all
close all
clc
define_constants; %打开这个函数可明确mpc的各个矩阵包含的信息，同时参见[1]
% [1]Appendix B Data File Format, MATPWER User s Manual Version 7.1

%% ***********Parameters **********
Years = 15; % Number of years
HoursPerYear = 8760; % Number of hours per year
Hours = 24; % Total number of hours
N = 30; % number of load nodes
L = 41; % number of all lines
r = 0.08;     % 折现率
r_u = 0.05;   %系统正电力备用约束
r_d = 0.02;
T_o = 25;     % 运行年限
annuity_factor = (r * (1 + r)^T_o) / ((1 + r)^T_o - 1);
K = 4; % number of coal generation types
%% 设置一个Original scene，计算潮流和发电成本
% 假设原有节点节点负荷
gen_node = [1,2,22,27,23];
gen_c = setdiff(1:N, gen_node);
gen_status = [1,1,1,1,1,0];
l_status = zeros(L,1);
l_E = [1,2,3,5,4,6,7,8,9,10,11,12,13,14,16,19,20,21,22,23,24,25,26,27,30,31,32,33,34,35,36,37,38]; % 已建设线路
%l_E = (1:L);
l_c = setdiff((1:L),l_E); %待建设线路选项
l_status(l_E)= 1;

% 计算当前线路连接状态下的潮流并画图
mpc = case30;
mpc.gen(:, 8) = gen_status;
mpc.branch(:, 11) = l_status;
result = runpf(mpc);
Sbase = mpc.baseMVA;  % unit:VA
M = 1e5;
g_max_all = [300,600,1000,1200]/Sbase;
%g_min_all = [0.7,0.7,0.55,0.55] .* g_max_all;
g_min_all = [0.5,0.5,0.35,0.35] .* g_max_all;
g_min_ccs = g_min_all/2;%碳捕集电厂灵活性运行
x_coal_max = [4,14,1,3];

%静态投资成本 单位：亿元
c_gen = [12.9,22,37.5,45]'*1e6;   % 四种不同类型的燃煤机组静态投资成本/亿元
c_gen_ccs = 1.182 * c_gen;        % 新建ccs成本
%运行成本
cost = [0.3171,0.3171,0.2856,0.2856]*1e5;   % 运行成本 单位：元/kWh
cost_ccs = [0.4134,0.4134,0.3694,0.3694]*1e5;   % 运行成本 单位：元/kWh
% 碳排放强度 单位：t/MWh
cei = [0.905,0.905,0.746,0.746]*1e2;        
cei_ccs = [0.113,0.113,0.093,0.093]*1e2;

carbon_tax = [120 126 132 138 145 151 157 163 169 176 182 188 194 200 206];         % 碳税﻿ 单位：元/tCO2
A_gen = c_gen * annuity_factor;
A_ccs = c_gen_ccs * annuity_factor;
p_max = mpc.branch(:,RATE_A)*50/Sbase;       %线路传输功率上限【原有线路传输功率太小了】
xb = mpc.branch(:,BR_X); %线路电抗
c_lines = xb*100;  %用线路电抗代表线路长度，得到线路建设成本c_lines

I = mpc.branch(:,F_BUS);
J = mpc.branch(:,T_BUS);
[Ainc] = makeIncidence(mpc); % branch-node incidence matrix
In = Ainc'; % node-branch incidence matrix, but with all lines closed

%生成一组24h负荷需求数据
pd = mpc.bus(:,PD)/Sbase; %负荷需求标幺值
System_demand = xlsread('gtepuc.xlsx',2,'B3:B26')/100;
P_load(:,:,1)=(System_demand .* pd')'*0.5;
growth_rate = 1.06; % 6% growth rate per year
for year = 2:Years
    P_load(:,:,year) = P_load(:,:,year-1) * growth_rate;
end
P_load_max = max(P_load, [], 2);
P_load_min = min(P_load, [], 2);
% 潮流结果
fprintf('线路潮流:\n');
disp(result.branch(:, [1, 2, 14]));
%% 绘图
G = digraph(result.branch(:, 1),result.branch(:, 2),result.branch(:, 14)/Sbase);
figure;
h = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);
% 设置节点坐标
%          1，  2，3，4，5，  6，  7， 8，  9，10，11，12，13，14，15，16， 17，18，  19， 20，21，22，23，24，  25，  26，27，28，29
h.XData = [0,  4, 2, 4, 10, 12, 12, 15, 10, 10, 7,  4,  1,  1, 4, 6,   8,  6,  8.5, 10, 11, 12, 7, 12, 10,  5.0, 7.5, 15, 1.0, 1.0];
h.YData = [0, -3, 0, 0, -3,  0, -3,  0,  0,  3, 0,  3,  3,  7.5, 10, 5,  5, 7.5, 7.5, 7.5, 5, 3, 10, 10,   12.5, 12.5, 15, 15, 15, 10];
highlight(h,I(l_status==1),J(l_status==1),'LineWidth',3,'EdgeColor','k'); %画出已建设线路
highlight(h,I(l_status==0),J(l_status==0),'LineStyle','-.','LineWidth',1,'EdgeColor','b'); %画出待建设线路选项
h.EdgeLabel = G.Edges.Weight;
title('初始线路');
for i = 1:size(mpc.gen, 1)
    node = mpc.gen(i, 1);
    power = mpc.gen(i, 2);
    label_str = sprintf('机组出力：%.2f', power/Sbase);
    text(h.XData(node)+0.2, h.YData(node)-0.1, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
end
for i= 1:N
    label_str = sprintf('负荷需求：%.2f',mpc.bus(i,PD)/Sbase);
    text(h.XData(i)-0.4, h.YData(i)+0.2, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
end

%% ***********Variable statement**********
% 投资决策变量
x_lines = binvar(L,Years);%是否建设线路L

x_gen_coal_1 = binvar(N,x_coal_max(1),Years);%在N个节点各建设几台1型燃煤机组
x_gen_coal_2 = binvar(N,x_coal_max(2),Years);%在N个节点各建设几台2型燃煤机组
x_gen_coal_3 = binvar(N,x_coal_max(3),Years);%在N个节点各建设几台3型燃煤机组
x_gen_coal_4 = binvar(N,x_coal_max(4),Years);%在N个节点各建设几台4型燃煤机组

x_gen_ccs_1 = binvar(N,x_coal_max(1),Years);%在N个节点各建设几台1型ccs
x_gen_ccs_2 = binvar(N,x_coal_max(2),Years);%在N个节点各建设几台2型ccs
x_gen_ccs_3 = binvar(N,x_coal_max(3),Years);%在N个节点各建设几台3型ccs
x_gen_ccs_4 = binvar(N,x_coal_max(4),Years);%在N个节点各建设几台4型ccs

x_gens = sdpvar(4,Years);%
x_gens_ccs = sdpvar(4,Years);%
total_capacity = sdpvar(1,Years);
% 投资状态变量
I_lines = binvar(L,Years);%是否已建设线路L
I_gen_coal_1 = binvar(N,x_coal_max(1),Years);%在N个节点是否已建设1型燃煤机组
I_gen_coal_2 = binvar(N,x_coal_max(2),Years);%在N个节点是否已建设2型燃煤机组
I_gen_coal_3 = binvar(N,x_coal_max(3),Years);%在N个节点是否已建设3型燃煤机组
I_gen_coal_4 = binvar(N,x_coal_max(4),Years);%在N个节点是否已建设4型燃煤机组
I_gen_ccs_1 = binvar(N,x_coal_max(1),Years);
I_gen_ccs_2 = binvar(N,x_coal_max(2),Years);
I_gen_ccs_3 = binvar(N,x_coal_max(3),Years);
I_gen_ccs_4 = binvar(N,x_coal_max(4),Years);
% 运行决策变量
theta = sdpvar(N,Hours,Years);
p = sdpvar(L,Hours,Years);
pd_shed = sdpvar(N,Hours,Years);
g_exist = sdpvar(N,Hours,Years);

%燃煤机组
g_coal_1 = sdpvar(N,x_coal_max(1),Hours,Years,'full');%节点N的第K台机组在t时段的输出功率
g_coal_2 = sdpvar(N,x_coal_max(2),Hours,Years,'full');
g_coal_3 = sdpvar(N,x_coal_max(3),Hours,Years,'full');
g_coal_4 = sdpvar(N,x_coal_max(4),Hours,Years,'full');
sum_N_g = sdpvar(N,Hours,Years);%6个节点的机组输出功率
sum_type_g = sdpvar(N,length(x_coal_max),Hours,Years,'full');%四种类型一共发了多少
%碳捕集机组
g_ccs_1 = sdpvar(N,x_coal_max(1),Hours,Years,'full');%节点N的第K台机组在t时段的输出功率
g_ccs_2 = sdpvar(N,x_coal_max(2),Hours,Years,'full');
g_ccs_3 = sdpvar(N,x_coal_max(3),Hours,Years,'full');
g_ccs_4 = sdpvar(N,x_coal_max(4),Hours,Years,'full');
sum_N_g_ccs = sdpvar(N,Hours,Years);%6个节点的机组输出功率
sum_type_g_ccs = sdpvar(N,length(x_coal_max),Hours,Years,'full');%四种类型一共发了多少

%x_gen_gas = binvar(3,5);
%x_gen_pws = binvar(3,2);
%x_gen_nuc = binvar(3,1);

%% ***********Constraints*************
%投资状态变量
Cons = [];
Cons = [Cons,x_gens(1,:) == squeeze(sum(sum(x_gen_coal_1, 2)))'];
Cons = [Cons,x_gens(2,:) == squeeze(sum(sum(x_gen_coal_2, 2)))'];
Cons = [Cons,x_gens(3,:) == squeeze(sum(sum(x_gen_coal_3, 2)))'];
Cons = [Cons,x_gens(4,:) == squeeze(sum(sum(x_gen_coal_4, 2)))'];
Cons = [Cons, x_gens <= repmat(x_coal_max', 1, Years)];%机组建设数目上限
Cons = [Cons,x_gens_ccs(1,:) == squeeze(sum(sum(x_gen_ccs_1, 2)))'];
Cons = [Cons,x_gens_ccs(2,:) == squeeze(sum(sum(x_gen_ccs_2, 2)))'];
Cons = [Cons,x_gens_ccs(3,:) == squeeze(sum(sum(x_gen_ccs_3, 2)))'];
Cons = [Cons,x_gens_ccs(4,:) == squeeze(sum(sum(x_gen_ccs_4, 2)))'];
Cons = [Cons, x_gens_ccs <= repmat(x_coal_max', 1, Years)];%机组建设数目上限

%投资状态变量
for year = 1:Years
    if year == 1
        % 第一年
        Cons = [Cons, I_lines(:,year) == l_status + x_lines(:,year)];
        Cons = [Cons, I_gen_coal_1(:,:,year) == x_gen_coal_1(:,:,year)];
        Cons = [Cons, I_gen_coal_2(:,:,year) == x_gen_coal_2(:,:,year)];
        Cons = [Cons, I_gen_coal_3(:,:,year) == x_gen_coal_3(:,:,year)];
        Cons = [Cons, I_gen_coal_4(:,:,year) == x_gen_coal_4(:,:,year)];
        Cons = [Cons, I_gen_ccs_1(:,:,year) == x_gen_ccs_1(:,:,year)];
        Cons = [Cons, I_gen_ccs_2(:,:,year) == x_gen_ccs_2(:,:,year)];
        Cons = [Cons, I_gen_ccs_3(:,:,year) == x_gen_ccs_3(:,:,year)];
        Cons = [Cons, I_gen_ccs_4(:,:,year) == x_gen_ccs_4(:,:,year)];
    else
        % 之后的年份投资状态变量等于上一年的状态变量加上本年的建设决策变量
        Cons = [Cons, I_lines(:,year) == I_lines(:,year-1) + x_lines(:,year)];
        Cons = [Cons, I_gen_coal_1(:,:,year) == I_gen_coal_1(:,:,year-1) + x_gen_coal_1(:,:,year)];
        Cons = [Cons, I_gen_coal_2(:,:,year) == I_gen_coal_2(:,:,year-1) + x_gen_coal_2(:,:,year)];
        Cons = [Cons, I_gen_coal_3(:,:,year) == I_gen_coal_3(:,:,year-1) + x_gen_coal_3(:,:,year)];
        Cons = [Cons, I_gen_coal_4(:,:,year) == I_gen_coal_4(:,:,year-1) + x_gen_coal_4(:,:,year)];
        Cons = [Cons, I_gen_ccs_1(:,:,year) == I_gen_ccs_1(:,:,year-1) + x_gen_ccs_1(:,:,year)];
        Cons = [Cons, I_gen_ccs_2(:,:,year) == I_gen_ccs_2(:,:,year-1) + x_gen_ccs_2(:,:,year)];
        Cons = [Cons, I_gen_ccs_3(:,:,year) == I_gen_ccs_3(:,:,year-1) + x_gen_ccs_3(:,:,year)];
        Cons = [Cons, I_gen_ccs_4(:,:,year) == I_gen_ccs_4(:,:,year-1) + x_gen_ccs_4(:,:,year)];

        % 防止重复建设：如果已经建设，后续年份不再建设
        Cons = [Cons, x_lines(:,year) <= 1 - I_lines(:,year-1)];
        Cons = [Cons, x_gen_coal_1(:,:,year) <= 1 - I_gen_coal_1(:,:,year-1)];
        Cons = [Cons, x_gen_coal_2(:,:,year) <= 1 - I_gen_coal_2(:,:,year-1)];
        Cons = [Cons, x_gen_coal_3(:,:,year) <= 1 - I_gen_coal_3(:,:,year-1)];
        Cons = [Cons, x_gen_coal_4(:,:,year) <= 1 - I_gen_coal_4(:,:,year-1)];
        Cons = [Cons, x_gen_ccs_1(:,:,year) <= 1 - I_gen_ccs_1(:,:,year-1)];
        Cons = [Cons, x_gen_ccs_2(:,:,year) <= 1 - I_gen_ccs_2(:,:,year-1)];
        Cons = [Cons, x_gen_ccs_3(:,:,year) <= 1 - I_gen_ccs_3(:,:,year-1)];
        Cons = [Cons, x_gen_ccs_4(:,:,year) <= 1 - I_gen_ccs_4(:,:,year-1)];
    end
    %新建机组方式只能有一种
    Cons = [Cons, x_gen_coal_1(:,:,year) + x_gen_ccs_1(:,:,year)<= 1];
    Cons = [Cons, x_gen_coal_2(:,:,year) + x_gen_ccs_2(:,:,year)<= 1];
    Cons = [Cons, x_gen_coal_3(:,:,year) + x_gen_ccs_3(:,:,year)<= 1];
    Cons = [Cons, x_gen_coal_4(:,:,year) + x_gen_ccs_4(:,:,year)<= 1];
end
% 只有[5,9,11,13,21,22,25,27,28]节点可以建设机组
Cons = [Cons, x_gen_coal_1((~ismember(1:N,[5,9,11,13,21,22,25,27,28])),:,:) == 0];
Cons = [Cons, x_gen_coal_2((~ismember(1:N,[5,9,11,13,21,22,25,27,28])),:,:) == 0];
Cons = [Cons, x_gen_coal_3((~ismember(1:N,[5,9,11,13,21,22,25,27,28])),:,:) == 0];
Cons = [Cons, x_gen_coal_4((~ismember(1:N,[5,9,11,13,21,22,25,27,28])),:,:) == 0];
Cons = [Cons, x_gen_ccs_1((~ismember(1:N,[5,9,11,13,21,22,25,27,28])),:,:) == 0];
Cons = [Cons, x_gen_ccs_2((~ismember(1:N,[5,9,11,13,21,22,25,27,28])),:,:) == 0];
Cons = [Cons, x_gen_ccs_3((~ismember(1:N,[5,9,11,13,21,22,25,27,28])),:,:) == 0];
Cons = [Cons, x_gen_ccs_4((~ismember(1:N,[5,9,11,13,21,22,25,27,28])),:,:) == 0];
% 只有[1,4,7,10,13]年可以建设机组
Cons = [Cons, x_gen_coal_1(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_coal_2(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_coal_3(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_coal_4(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_ccs_1(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_ccs_2(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_ccs_3(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_ccs_4(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
%% Cons1: 直流潮流约束+TEP
for y = 1:Years
    for h = 1:Hours
        Cons = [Cons,-(1 - I_lines(:,y)) * M <= In'*theta(:,h,y) - p(:,h,y).* xb];
        Cons = [Cons,In'*theta(:,h,y) - p(:,h,y).* xb <= (1 - I_lines(:,y)) * M];
        Cons = [Cons,sum_N_g(:,h,y) == sum(g_coal_1(:,:,h,y), 2) + sum(g_coal_2(:,:,h,y), 2) + sum(g_coal_3(:,:,h,y), 2) + sum(g_coal_4(:,:,h,y), 2)];%每个节点所有机组在某一时刻的总输出功率的变量
        Cons = [Cons,sum_N_g_ccs(:,h,y) == sum(g_ccs_1(:,:,h,y), 2) + sum(g_ccs_2(:,:,h,y), 2) + sum(g_ccs_3(:,:,h,y), 2) + sum(g_ccs_4(:,:,h,y), 2)];%每个节点所有碳捕集机组在某一时刻的总输出功率的变量
        Cons = [Cons,In * p(:,h,y) == sum_N_g(:,h,y) + sum_N_g_ccs(:,h,y) + g_exist(:,h,y) - (P_load(:,h,y) - pd_shed(:,h,y)) ];
        Cons = [Cons,theta(1,h,y) == 0];
        Cons = [Cons,- I_lines(:,y) .* p_max <= p(:,h,y)];%线路容量下限
        Cons = [Cons,p(:,h,y) <= I_lines(:,y) .* p_max];%线路容量上限
        Cons = [Cons,P_load(:,h,y) >= pd_shed(:,h,y) >= 0];
        
    end
end
%下面这个循环是为了保证规划结果便于观测，无物理意义
for j = 2:x_coal_max(1)
        Cons = [Cons, x_gen_coal_1(:,j,:) <= x_gen_coal_1(:,j-1,:)];
end
for j = 2:x_coal_max(2)
        Cons = [Cons, x_gen_coal_2(:,j,:) <= x_gen_coal_2(:,j-1,:)];
end
for j = 2:x_coal_max(4)
        Cons = [Cons, x_gen_coal_4(:,j,:) <= x_gen_coal_4(:,j-1,:)];
end
%% Cons2: 机组发电功率约束
% 原有机组
Cons = [Cons, g_exist(gen_c,:,:) == 0];%初始条件
Cons = [Cons,g_min_all(1) <= g_exist(gen_node,:,:)]; 
Cons = [Cons,g_exist(gen_node,:,:)<= g_max_all(1)] ;
% 新增机组
for i=1:N
    %Cons = [Cons, u(i,k,t) <= x_gen_coal(i,k)];%运行的机组和投建机组的关系
    %机组发电功率上限
    for t = 1:24
        Cons = [Cons, I_gen_coal_1(i,:,:) .* g_min_all(1) <= g_coal_1(i,:,t,:)];
        Cons = [Cons, g_coal_1(i,:,t,:) <= I_gen_coal_1(i,:,:) .* g_max_all(1)];
        Cons = [Cons, I_gen_coal_2(i,:,:) .* g_min_all(2) <= g_coal_2(i,:,t,:)];
        Cons = [Cons, g_coal_2(i,:,t,:) <= I_gen_coal_2(i,:,:) .* g_max_all(2)];
        Cons = [Cons, I_gen_coal_3(i,:,:) .* g_min_all(3) <= g_coal_3(i,:,t,:)];
        Cons = [Cons, g_coal_3(i,:,t,:) <= I_gen_coal_3(i,:,:) .* g_max_all(3)];
        Cons = [Cons, I_gen_coal_4(i,:,:) .* g_min_all(4) <= g_coal_4(i,:,t,:)];
        Cons = [Cons, g_coal_4(i,:,t,:) <= I_gen_coal_4(i,:,:) .* g_max_all(4)];
        Cons = [Cons, I_gen_ccs_1(i,:,:) .* g_min_ccs(1) <= g_ccs_1(i,:,t,:)];
        Cons = [Cons, g_ccs_1(i,:,t,:) <= I_gen_ccs_1(i,:,:) .* g_max_all(1)];
        Cons = [Cons, I_gen_ccs_2(i,:,:) .* g_min_ccs(2) <= g_ccs_2(i,:,t,:)];
        Cons = [Cons, g_ccs_2(i,:,t,:) <= I_gen_ccs_2(i,:,:) .* g_max_all(2)];
        Cons = [Cons, I_gen_ccs_3(i,:,:) .* g_min_ccs(3) <= g_ccs_3(i,:,t,:)];
        Cons = [Cons, g_ccs_3(i,:,t,:) <= I_gen_ccs_3(i,:,:) .* g_max_all(3)];
        Cons = [Cons, I_gen_ccs_4(i,:,:) .* g_min_ccs(4) <= g_ccs_4(i,:,t,:)];
        Cons = [Cons, g_ccs_4(i,:,t,:) <= I_gen_ccs_4(i,:,:) .* g_max_all(4)];
    end
end


%% Cons3: 系统日电力备用约束

for y = 1:Years
    Cons = [Cons,total_capacity(1,y) == sum(g_max_all * (x_gens + x_gens_ccs)) + length(gen_node) * g_max_all(1)];
    for h = 1:Hours
        Cons = [Cons, total_capacity(1,y) >= (P_load_max(:,:,y)-pd_shed(:,h,y)) * (1 + r_u)];
    end
end
%% 计算投资成本
Obj_inv = 0;
for year = 1:Years
    Obj_inv = Obj_inv + sum(c_lines .* x_lines(:,year));
        for i = 1:N
            for t = year:Years
                for j = 1:size(x_gen_coal_1, 2)
                    Obj_inv = Obj_inv + A_gen(1) * I_gen_coal_1(i, j, year) / (1 + r)^(t - year);
                end
                for j = 1:size(x_gen_coal_2, 2)
                    Obj_inv = Obj_inv + A_gen(2) * I_gen_coal_2(i, j, year) / (1 + r)^(t - year);
                end
                for j = 1:size(x_gen_coal_3, 2)
                    Obj_inv = Obj_inv + A_gen(3) * I_gen_coal_3(i, j, year) / (1 + r)^(t - year);
                end
                for j = 1:size(x_gen_coal_4, 2)
                    Obj_inv = Obj_inv + A_gen(4) * I_gen_coal_4(i, j, year) / (1 + r)^(t - year);
                end
                for j = 1:size(x_gen_coal_1, 2)
                    Obj_inv = Obj_inv + A_ccs(1) * I_gen_ccs_1(i, j, year) / (1 + r)^(t - year);
                end
                for j = 1:size(x_gen_coal_2, 2)
                    Obj_inv = Obj_inv + A_ccs(2) * I_gen_ccs_2(i, j, year) / (1 + r)^(t - year);
                end
                for j = 1:size(x_gen_coal_3, 2)
                    Obj_inv = Obj_inv + A_ccs(3) * I_gen_ccs_3(i, j, year) / (1 + r)^(t - year);
                end
                for j = 1:size(x_gen_coal_4, 2)
                    Obj_inv = Obj_inv + A_ccs(4) * I_gen_ccs_4(i, j, year) / (1 + r)^(t - year);
                end
            end
        end       
end
%发电成本
Obj_ope = sdpvar(3,Hours,Years);
Cons = [Cons,sum_type_g(:,1,:,:) == sum(g_coal_1,2)];
Cons = [Cons,sum_type_g(:,2,:,:) == sum(g_coal_2,2)];
Cons = [Cons,sum_type_g(:,3,:,:) == sum(g_coal_3,2)];
Cons = [Cons,sum_type_g(:,4,:,:) == sum(g_coal_4,2)];
Cons = [Cons,sum_type_g_ccs(:,1,:,:) == sum(g_ccs_1,2)];
Cons = [Cons,sum_type_g_ccs(:,2,:,:) == sum(g_ccs_2,2)];
Cons = [Cons,sum_type_g_ccs(:,3,:,:) == sum(g_ccs_3,2)];
Cons = [Cons,sum_type_g_ccs(:,4,:,:) == sum(g_ccs_4,2)];
ope_cost_coal = sdpvar(N,Hours,Years);
ope_cost_ccs = sdpvar(N,Hours,Years);
Obj_ope_total = 0;
for t = 1:Hours
    for y = 1:Years
            Obj_ope_total = Obj_ope_total + (M * sum(pd_shed(:,t,y)) + sum(cost(1).*g_exist(:,t,y)))*365;%原有机组发电成本
        for i = 1:4
            Obj_ope_total = Obj_ope_total + sum(sum(cost(i).*sum_type_g(:,i,t,y)))*365;
            Obj_ope_total = Obj_ope_total + sum(sum(cost_ccs(i).*sum_type_g_ccs(:,i,t,y)))*365;            
        end

    end
end      



%Obj = Obj_inv +Obj_ope_total ; %+ sum(sum(Obj_carbon_coal)) + sum(sum(Obj_carbon_ccs))+sum(sum(Obj_carbon_gas+ Obj_u + Obj_up + Obj_down;
Obj = Obj_inv+Obj_ope_total;
% Solve the problem
ops = sdpsettings('verbose',2,'solver','gurobi','gurobi.Heuristics',0.9);
sol = optimize(Cons,Obj,ops);


%% 规划结果
s_x_lines = value(x_lines);
s_x_gen_coal_1 = value(x_gen_coal_1);
s_x_gen_coal_2 = value(x_gen_coal_2);
s_x_gen_coal_3 = value(x_gen_coal_3);
s_x_gen_coal_4 = value(x_gen_coal_4);
s_x_gen_ccs_1 = value(x_gen_ccs_1);
s_x_gen_ccs_2 = value(x_gen_ccs_2);
s_x_gen_ccs_3 = value(x_gen_ccs_3);
s_x_gen_ccs_4 = value(x_gen_ccs_4);

s_I_lines = value(I_lines);
s_I_gen_coal_1 = value(I_gen_coal_1);
s_I_gen_coal_2 = value(I_gen_coal_2);
s_I_gen_coal_3 = value(I_gen_coal_3);
s_I_gen_coal_4 = value(I_gen_coal_4);
s_I_gen_ccs_1 = value(I_gen_ccs_1);
s_I_gen_ccs_2 = value(I_gen_ccs_2);
s_I_gen_ccs_3 = value(I_gen_ccs_3);
s_I_gen_ccs_4 = value(I_gen_ccs_4);

s_x_gens = value(x_gens);
s_x_gens_ccs = value(x_gens_ccs);
s_p = value(p);
s_pd_shed = value(pd_shed);
s_theta = value(theta);
s_g_coal_1 = value(g_coal_1);
s_g_coal_2 = value(g_coal_2);
s_g_coal_3 = value(g_coal_3);
s_g_coal_4 = value(g_coal_4);
s_sum_N_g = value(sum_N_g);
sum_type_g(:,1,:,:) = sum(g_coal_1,2);
sum_type_g(:,2,:,:) = sum(g_coal_2,2);
sum_type_g(:,3,:,:) = sum(g_coal_3,2);
sum_type_g(:,4,:,:) = sum(g_coal_4,2);
s_sum_type_g = value(sum_type_g);
sum_type_g_ccs(:,1,:,:) = sum(g_ccs_1,2);
sum_type_g_ccs(:,2,:,:) = sum(g_ccs_2,2);
sum_type_g_ccs(:,3,:,:) = sum(g_ccs_3,2);
sum_type_g_ccs(:,4,:,:) = sum(g_ccs_4,2);
s_sum_type_g_ccs = value(sum_type_g_ccs);

s_g_exist = value(g_exist);
s_Obj = value(Obj);
s_Obj_inv = value(Obj_inv);
s_Obj_ope = value(Obj_ope);

%% 绘制规划结果
figure;
yearGroup = uibuttongroup('Position', [0.05 0 0.9 0.15], 'Title', '选择年份');
% 创建年份选择按钮
year1Button = uicontrol(yearGroup, 'Style', 'radiobutton', 'String', '第1个规划周期', 'Position', [20 20 100 30]);
year2Button = uicontrol(yearGroup, 'Style', 'radiobutton', 'String', '第2个规划周期', 'Position', [140 20 100 30]);
year3Button = uicontrol(yearGroup, 'Style', 'radiobutton', 'String', '第3个规划周期', 'Position', [260 20 100 30]);
year4Button = uicontrol(yearGroup, 'Style', 'radiobutton', 'String', '第4个规划周期', 'Position', [380 20 100 30]);
year5Button = uicontrol(yearGroup, 'Style', 'radiobutton', 'String', '第5个规划周期', 'Position', [500 20 100 30]);

% 创建按钮回调函数
set(year1Button, 'Callback', @(src, event) plotResults(1,Hours,s_Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,I,J,l_E));
set(year2Button, 'Callback', @(src, event) plotResults(4,Hours,s_Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,I,J,l_E));
set(year3Button, 'Callback', @(src, event) plotResults(7,Hours,s_Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,I,J,l_E));
set(year4Button, 'Callback', @(src, event) plotResults(10,Hours,s_Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,I,J,l_E));
set(year5Button, 'Callback', @(src, event) plotResults(13,Hours,s_Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,I,J,l_E));