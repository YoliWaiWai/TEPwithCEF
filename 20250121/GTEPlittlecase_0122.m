%% 一个简单的输电网扩展规划算例示意
% 基于matpower中的30节点网络，case30.m
clear all
close all
clc
define_constants; %打开这个函数可明确mpc的各个矩阵包含的信息，同时参见[1]
% [1]Appendix B Data File Format, MATPWER User s Manual Version 7.1
%% ***********Parameters **********
Years = 15; % Number of years
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
gen_status = [1,1,1,1,1,1];
l_status = zeros(L,1);
l_E = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,19,20,22,23,24,25,26,27,29,30,31,32,33,34,35,36,37,38]; % 已建设线路
l_c = setdiff((1:L),l_E); %待建设线路选项
l_status(l_E)= 1;
% 计算当前线路连接状态下的潮流并画图
mpc = case30_modified;
mpc.gen(:, 8) = gen_status;
mpc.branch(:, 11) = l_status;
result = runpf(mpc);
% 检查收敛性
if result.success
    disp('潮流计算收敛。');
    % 输出最终的发电机功率和负荷功率
    total_gen_power = sum(result.gen(:, 2)); % 有功功率输出
    total_load_power = sum(mpc.bus(:, 3));   % 有功负荷
    disp(['最终发电机总功率: ', num2str(total_gen_power), ' MW']);
    disp(['最终负荷总功率: ', num2str(total_load_power), ' MW']);
else
    disp('潮流计算不收敛。');
end
% 潮流结果
fprintf('线路潮流:\n');
disp(result.branch(:, [1, 2, 14]));
Sbase = mpc.baseMVA;  % unit:VA
I = result.branch(:,1);
J = result.branch(:,2);
[Ainc] = makeIncidence(mpc); % branch-node incidence matrix
In = Ainc'; % node-branch incidence matrix, but with all lines closed
% 绘图
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
for i = 1:size(result.gen, 1)
    node = result.gen(i, 1);
    power = result.gen(i, 2);
    label_str = sprintf('机组出力：%.2f', power/Sbase);
    text(h.XData(node)+0.2, h.YData(node)-0.1, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'r', 'FontSize', 8);
end
for i= 1:N
    label_str = sprintf('负荷需求：%.2f',result.bus(i,PD)/Sbase);
    text(h.XData(i)-0.4, h.YData(i)+0.4, label_str, ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', 'Color', 'b', 'FontSize', 8);
end

M = 1e7;
g_max_all = [300,600,1000,1200]/Sbase;%单位MW
g_max_gas = [180,220]/Sbase;
g_min_all = [0.5,0.45,0.4,0.3] .* g_max_all;
g_max_ccs = g_max_all * 0.9 ;
g_min_ccs = [0.45,0.35,0.30,0.25] .* g_max_all;%碳捕集电厂
g_min_gas = g_max_gas * 0.25;
x_coal_max = [4,5,1,3];%可规划的最大台数
x_gas_max = [4,5];
p_max = mpc.branch(:,RATE_A)*12/Sbase;       %线路传输功率上限
xb = mpc.branch(:,BR_X); %线路电抗
c_lines = xb*100;  %用线路电抗代表线路长度，得到线路建设成本c_lines
%静态投资成本 单位：亿元
c_gen = [12.9,22,37.5,45]' * 1e8;   % 四种不同类型的燃煤机组静态投资成本/亿元
c_gen_ccs = 1.182 * c_gen;        % 新建ccs成本
c_gen_gas = [5.94,6.60]' * 1e8;
%c_gen_trans = 0.186 * c_gen;
c_gen_trans = 0 * c_gen;
A_gen = c_gen * annuity_factor;
A_ccs = c_gen_ccs * annuity_factor;
A_gas = c_gen_gas * annuity_factor;
A_gen_trans = c_gen_trans * annuity_factor;

%运行成本
cost =     [0.3171,0.3171,0.2856,0.2856] * 1e5;   % 运行成本 单位：元/kWh   每100MW费用
cost_ccs = [0.4134,0.3973,0.3747,0.3694] * 1e5;   % 运行成本 单位：元/kWh
cost_gas = [0.432,0.396] * 1e5;
K_q = 4000;%弃风惩罚成本系数
% 碳排放强度 单位：t/MWh
cei =     [0.905,0.856,0.772,0.746] * 1e2;
cei_ccs = [0.113,0.108,0.098,0.093] * 1e2;
cei_gas = [0.45,0.44] * 1e2;
% 碳排放基准值
% year         1     2    3     4    5    6    7    8    9    10    11    12    13    14    15
carbon_tax =     [145   151   157   160   164   168   172   175   178   181   184   187   191   194   197];         % 碳税﻿ 单位：元/tCO2
carbon_quota =   [0.7861 0.7822 0.778 0.774 0.770 0.766 0.762 0.758 0.754 0.750 0.746 0.742 0.738 0.734 0.730;%300MW等级以上常规燃煤机组
                  0.7984 0.7944 0.79  0.786 0.782 0.778 0.774 0.77  0.766 0.762 0.758 0.754 0.75  0.746 0.742]* 1e2;%300MW等级以下常规燃煤机组
carbon_quota_gas = [0.3305 0.3288 0.3262 0.3240 0.3185 0.3164 0.3145 0.3128 0.3111 0.3098 0.3087 0.3079 0.3067 0.3055 0.304]* 1e2;%燃煤机组碳排放基准值
%生成一组24h负荷需求数据
pd = mpc.bus(:,PD)/Sbase; %负荷需求标幺值
pd_total = sum(pd);
System_demand = xlsread('gtepuc.xlsx',2,'C3:C26')/Sbase;  
% 风电预测功率
P_predict23 = [299, 267, 280, 284, 329, 289, 168, 159, 186, 198, 131, 85, 58, 91, 116, 139, 149, 191, 267, 291, 300, 334, 353, 342]'/Sbase;
P_predict27 = [339, 287, 449, 471, 512, 530, 527, 641, 634, 519, 401, 634, 589, 530, 512, 505, 206, 85, 81, 80, 83, 110, 353, 523]'/Sbase;
% 净负荷
NetLoad = System_demand - P_predict23 - P_predict27;
% 30节点24小时负荷数据
P_load(:,:,1)=((System_demand) .* (pd/pd_total)')';%P_load（30*24*6）
% 风功率和系统负荷需求
figure
plot(P_predict23 + P_predict27,'c-<','LineWidth',1.5)
hold on
plot(System_demand*2.53,'m-s','LineWidth',1.5)
plot(NetLoad,'r->','LineWidth',1.5)
legend('风电出力','电负荷','净负荷')
xlabel('时间/h');
ylabel('功率/100MW');
title('净负荷初始数据');
growth_rate = 1.06; % 6% growth rate per year
for year = 2:Years
    P_load(:,:,year) = P_load(:,:,year-1) * growth_rate;
end
P_load_max = zeros(1, Years);
P_load_min = zeros(1, Years);
for y = 1:Years
    total_load_per_hour = sum(P_load(:,:,y), 1);
    P_load_max(y) = max(total_load_per_hour);
    P_load_min(y) = min(total_load_per_hour);
end

%% ***********Variable statement**********
%% 投资决策变量
x_lines = binvar(L,Years);%是否建设线路L

x_gen_coal_1 = binvar(N,x_coal_max(1),Years);%在N个节点各建设几台1型燃煤机组
x_gen_coal_2 = binvar(N,x_coal_max(2),Years);%在N个节点各建设几台2型燃煤机组
x_gen_coal_3 = binvar(N,x_coal_max(3),Years);%在N个节点各建设几台3型燃煤机组
x_gen_coal_4 = binvar(N,x_coal_max(4),Years);%在N个节点各建设几台4型燃煤机组

x_gen_ccs_1 = binvar(N,x_coal_max(1),Years);%在N个节点各建设几台1型ccs
x_gen_ccs_2 = binvar(N,x_coal_max(2),Years);%在N个节点各建设几台2型ccs
x_gen_ccs_3 = binvar(N,x_coal_max(3),Years);%在N个节点各建设几台3型ccs
x_gen_ccs_4 = binvar(N,x_coal_max(4),Years);%在N个节点各建设几台4型ccs

x_gen_gas_1 = binvar(N,x_gas_max(1),Years);%在N个节点各建设几台1型gas
x_gen_gas_2 = binvar(N,x_gas_max(2),Years);%在N个节点各建设几台2型gas

x_gens = sdpvar(4,Years);
x_gens_ccs = sdpvar(4,Years);
x_gens_gas = sdpvar(2,Years);

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
I_gen_gas_1 = binvar(N,x_gas_max(1),Years);
I_gen_gas_2 = binvar(N,x_gas_max(2),Years);

%% 改造决策变量
% 1.原有的三台燃煤机组是否改造为碳捕集机组
x_trans_gexist = binvar(3,Years);

% 改造状态变量
% 1.原有的三台燃煤机组是否改造为碳捕集机组
I_trans_gexist = binvar(3,Years);

% 运行决策变量
theta = sdpvar(N,Hours,Years);
p = sdpvar(L,Hours,Years);
pd_shed = sdpvar(N,Hours,Years);
g_exist = sdpvar(N,Hours,Years);
g_exist_c = sdpvar(N,Hours,Years);
g_exist_w1 = sdpvar(1,Hours,Years);
g_exist_w2 = sdpvar(1,Hours,Years);
% u3 = binvar(N,x_coal_max(3),Hours,Years,'full');%节点N的第K台机组在t时段是否运行
% v3 = binvar(N,x_coal_max(3),Hours,Years,'full');%节点N的第K台机组在t时刻是否开启
% w3 = binvar(N,x_coal_max(3),Hours,Years,'full');%节点N的第K台机组在t时刻是否关停
%燃煤机组
g_coal_1 = sdpvar(N,x_coal_max(1),Hours,Years,'full');%节点N的第K台机组在t时段的输出功率
g_coal_2 = sdpvar(N,x_coal_max(2),Hours,Years,'full');
g_coal_3 = sdpvar(N,x_coal_max(3),Hours,Years,'full');
g_coal_4 = sdpvar(N,x_coal_max(4),Hours,Years,'full');
sum_N_g = sdpvar(N,Hours,Years);%N个节点的机组输出功率
sum_type_g = sdpvar(N,length(x_coal_max),Hours,Years,'full');%四种类型一共发了多少
sum_coal = sdpvar(length(x_coal_max),Years);
%碳捕集机组
g_ccs_1 = sdpvar(N,x_coal_max(1),Hours,Years,'full');%节点N的第K台机组在t时段的输出功率
g_ccs_2 = sdpvar(N,x_coal_max(2),Hours,Years,'full');
g_ccs_3 = sdpvar(N,x_coal_max(3),Hours,Years,'full');
g_ccs_4 = sdpvar(N,x_coal_max(4),Hours,Years,'full');
sum_N_g_ccs = sdpvar(N,Hours,Years);%6个节点的机组输出功率
sum_type_g_ccs = sdpvar(N,length(x_coal_max),Hours,Years,'full');%四种类型一共发了多少
sum_ccs = sdpvar(length(x_coal_max),Years);
%燃气机组
g_gas_1 = sdpvar(N,x_gas_max(1),Hours,Years,'full');%节点N的第K台机组在t时段的输出功率
g_gas_2 = sdpvar(N,x_gas_max(2),Hours,Years,'full');

sum_N_g_gas = sdpvar(N,Hours,Years);%N个节点的机组输出功率
sum_type_g_gas = sdpvar(N,length(x_gas_max),Hours,Years,'full');%四种类型一共发了多少
sum_gas = sdpvar(length(x_gas_max),Years);


%% ***********Constraints*************
%% Cons0: 投资状态
display('***开始建立投资状态相关约束！***')
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
Cons = [Cons,x_gens_gas(1,:) == squeeze(sum(sum(x_gen_gas_1, 2)))'];
Cons = [Cons,x_gens_gas(2,:) == squeeze(sum(sum(x_gen_gas_2, 2)))'];
Cons = [Cons, x_gens_gas <= repmat(x_gas_max', 1, Years)];%机组建设数目上限
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

        Cons = [Cons, I_gen_gas_1(:,:,year) == x_gen_gas_1(:,:,year)];
        Cons = [Cons, I_gen_gas_2(:,:,year) == x_gen_gas_2(:,:,year)];

        Cons = [Cons, I_trans_gexist(:,year) == x_trans_gexist(:,year)];
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

        Cons = [Cons, I_gen_gas_1(:,:,year) == I_gen_gas_1(:,:,year-1) + x_gen_gas_1(:,:,year)];
        Cons = [Cons, I_gen_gas_2(:,:,year) == I_gen_gas_2(:,:,year-1) + x_gen_gas_2(:,:,year)];

        Cons = [Cons, I_trans_gexist(:,year) == I_trans_gexist(:,year-1) + x_trans_gexist(:,year)];

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

        Cons = [Cons, x_gen_gas_1(:,:,year) <= 1 - I_gen_gas_1(:,:,year-1)];
        Cons = [Cons, x_gen_gas_2(:,:,year) <= 1 - I_gen_gas_2(:,:,year-1)];

        Cons = [Cons, x_trans_gexist(:,year) <= 1 - I_trans_gexist(:,year-1)];

    end
%     %新建机组方式只能有一种
%     Cons = [Cons, x_gen_coal_1(:,:,year) + x_gen_ccs_1(:,:,year)<= 1];
%     Cons = [Cons, x_gen_coal_2(:,:,year) + x_gen_ccs_2(:,:,year)<= 1];
%     Cons = [Cons, x_gen_coal_3(:,:,year) + x_gen_ccs_3(:,:,year)<= 1];
%     Cons = [Cons, x_gen_coal_4(:,:,year) + x_gen_ccs_4(:,:,year)<= 1];
end
% 只有[5,9,11,13,21,22,25,27,28]节点可以建设机组
Cons = [Cons, x_gen_coal_1((~ismember(1:N,[9,11,13,21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_coal_2((~ismember(1:N,[9,11,13,21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_coal_3((~ismember(1:N,[9,11,13,21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_coal_4((~ismember(1:N,[9,11,13,21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_ccs_1((~ismember(1:N,[9,11,13,21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_ccs_2((~ismember(1:N,[9,11,13,21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_ccs_3((~ismember(1:N,[9,11,13,21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_ccs_4((~ismember(1:N,[9,11,13,21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_gas_1((~ismember(1:N,[21,22,25,27])),:,:) == 0];
Cons = [Cons, x_gen_gas_2((~ismember(1:N,[21,22,25,27])),:,:) == 0];

% 只有[  ]年可以建设机组
Cons = [Cons, x_gen_coal_1(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_coal_2(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_coal_3(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_coal_4(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_ccs_1(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_ccs_2(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_ccs_3(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_ccs_4(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_gas_1(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_gen_gas_2(:,:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
Cons = [Cons, x_trans_gexist(:,(~ismember(1:Years,[1,4,7,10,13]))) == 0];
display('***投资状态相关约束 建立完成！***')
%% Cons1: 直流潮流约束+TEP
display('***开始建立 直流潮流约束+TEP 相关约束！***')
for y = 1:Years
    for h = 1:Hours
        Cons = [Cons,-(1 - I_lines(:,y)) * M <= In'*theta(:,h,y) - p(:,h,y).* xb];
        Cons = [Cons,In'*theta(:,h,y) - p(:,h,y).* xb <= (1 - I_lines(:,y)) * M];
        Cons = [Cons,sum_N_g(:,h,y) == sum(g_coal_1(:,:,h,y), 2) + sum(g_coal_2(:,:,h,y), 2) + sum(g_coal_3(:,:,h,y), 2) + sum(g_coal_4(:,:,h,y), 2)];%每个节点所有机组在某一时刻的总输出功率的变量
        Cons = [Cons,sum_N_g_ccs(:,h,y) == sum(g_ccs_1(:,:,h,y), 2) + sum(g_ccs_2(:,:,h,y), 2) + sum(g_ccs_3(:,:,h,y), 2) + sum(g_ccs_4(:,:,h,y), 2)];%每个节点所有碳捕集机组在某一时刻的总输出功率的变量
        Cons = [Cons,sum_N_g_gas(:,h,y) == sum(g_gas_1(:,:,h,y), 2) + sum(g_gas_2(:,:,h,y), 2)];%每个节点所有燃气机组在某一时刻的总输出功率的变量
        Cons = [Cons,In * p(:,h,y) == sum_N_g(:,h,y) + sum_N_g_ccs(:,h,y) + sum_N_g_gas(:,h,y) + g_exist(:,h,y) - (P_load(:,h,y) - pd_shed(:,h,y)) ];
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
display('***直流潮流约束+TEP 相关约束 建立完成！***')
%% Cons2: 机组发电功率约束
display('***开始建立 机组发电功率 相关约束！***')
% 原有机组
gen_node = [1,2,22];
gen_c = setdiff(1:N, gen_node);
Cons = [Cons,g_exist_c(gen_c,:,:) == 0];%初始条件
for i = 1:length(gen_node)
    node = gen_node(i);
    for year = 1:Years
            Cons = [Cons, g_min_all(1) * (1 - I_trans_gexist(i, year)) + g_min_ccs(1) * I_trans_gexist(i, year) <= g_exist_c(node, :, year)];
            Cons = [Cons, g_exist_c(node, :, year) <= g_max_all(1) * (1 - I_trans_gexist(i, year)) + g_max_ccs(1) * I_trans_gexist(i, year)];
    end
end
% 对于 23 和 27 节点，分别加入风电出力
for y = 1:Years
    for h = 1:Hours
        Cons = [Cons, 0 <= g_exist_w1(1, h, y) <= P_predict23(h)];
        Cons = [Cons, 0 <= g_exist_w2(1, h, y) <= P_predict27(h)];
        Cons = [Cons, g_exist(23, h, y) == g_exist_c(23, h, y) + g_exist_w1(1,h,y)];
        Cons = [Cons, g_exist(27, h, y) == g_exist_c(27, h, y) + g_exist_w2(1,h,y)];
        other_nodes = setdiff(1:N, [23, 27]); % 排除23和27节点
        for i = other_nodes
            Cons = [Cons, g_exist(i, h, y) == g_exist_c(i, h, y)];
        end
    end
end
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
        Cons = [Cons, g_ccs_1(i,:,t,:) <= I_gen_ccs_1(i,:,:) .* g_max_ccs(1)];
        Cons = [Cons, I_gen_ccs_2(i,:,:) .* g_min_ccs(2) <= g_ccs_2(i,:,t,:)];
        Cons = [Cons, g_ccs_2(i,:,t,:) <= I_gen_ccs_2(i,:,:) .* g_max_ccs(2)];
        Cons = [Cons, I_gen_ccs_3(i,:,:) .* g_min_ccs(3) <= g_ccs_3(i,:,t,:)];
        Cons = [Cons, g_ccs_3(i,:,t,:) <= I_gen_ccs_3(i,:,:) .* g_max_ccs(3)];
        Cons = [Cons, I_gen_ccs_4(i,:,:) .* g_min_ccs(4) <= g_ccs_4(i,:,t,:)];
        Cons = [Cons, g_ccs_4(i,:,t,:) <= I_gen_ccs_4(i,:,:) .* g_max_ccs(4)];

        Cons = [Cons, I_gen_gas_1(i,:,:) .* g_min_gas(1) <= g_gas_1(i,:,t,:)];
        Cons = [Cons, g_gas_1(i,:,t,:) <= I_gen_gas_1(i,:,:) .* g_max_gas(1)];
        Cons = [Cons, I_gen_gas_2(i,:,:) .* g_min_gas(2) <= g_gas_2(i,:,t,:)];
        Cons = [Cons, g_gas_2(i,:,t,:) <= I_gen_gas_2(i,:,:) .* g_max_gas(2)];
    end
end
display('*** 机组发电功率 相关约束 建立完成！***')

%% Cons3: 系统日电力备用约束
display('***开始建立 Cons3: 系统日电力备用约束！***')
total_capacity_yearly = sdpvar(1,Years);
total_coal_ccs_capacity_y= sdpvar(1,Years);
total_gas_capacity_y= sdpvar(1,Years);
for y = 1:Years
    % 计算每年的总容量
    Cons = [Cons,total_coal_ccs_capacity_y(y) == sum(sum(I_gen_coal_1(:,:,y),2)).*g_max_all(1) + sum(g_max_all(1) * (1 - I_trans_gexist(:,y)) + g_max_ccs(1) * I_trans_gexist(:,y))+...
                                sum(sum(I_gen_coal_2(:,:,y),2)).*g_max_all(2) + ...
                                sum(sum(I_gen_coal_3(:,:,y),2)).*g_max_all(3) + ...
                                sum(sum(I_gen_coal_4(:,:,y),2)).*g_max_all(4) + ...
                                sum(sum(I_gen_ccs_1(:,:,y),2)).*g_max_all(1) + ...
                                sum(sum(I_gen_ccs_2(:,:,y),2)).*g_max_all(2) + ...
                                sum(sum(I_gen_ccs_3(:,:,y),2)).*g_max_all(3) + ...
                                sum(sum(I_gen_ccs_4(:,:,y),2)).*g_max_all(4)];
    
    Cons = [Cons,total_gas_capacity_y(y) == sum(sum(I_gen_gas_1(:,:,y),2)).*g_max_gas(1) + ...
                           sum(sum(I_gen_gas_2(:,:,y),2)).*g_max_gas(2)];
    
    Cons = [Cons,total_capacity_yearly(y) == total_coal_ccs_capacity_y(y) + total_gas_capacity_y(y)];

    
    % 系统容量备用约束
    Cons = [Cons, total_capacity_yearly(y) >= (1 + r_u) * P_load_max(y)];
end
display('***Cons3: 系统日电力备用约束 建立完成！***')
%% Obj: 计算投资成本
display('***开始建立 目标函数 表达式！***')
Obj_inv = 0;
for year = 1:Years
    Obj_inv = Obj_inv + sum(c_lines .* x_lines(:,year));
        for t = year:Years
            %% 常规燃煤机组
            Obj_inv = Obj_inv + A_gen(1) / (1 + r)^(t - year) * sum(sum(I_gen_coal_1(:, :, year)));
            Obj_inv = Obj_inv + A_gen(2) / (1 + r)^(t - year) * sum(sum(I_gen_coal_2(:, :, year)));
            Obj_inv = Obj_inv + A_gen(3) / (1 + r)^(t - year) * sum(sum(I_gen_coal_3(:, :, year)));
            Obj_inv = Obj_inv + A_gen(4) / (1 + r)^(t - year) * sum(sum(I_gen_coal_4(:, :, year)));
            %% 碳捕集机组
            Obj_inv = Obj_inv + A_ccs(1) / (1 + r)^(t - year) * sum(sum(I_gen_ccs_1(:, :, year)));
            Obj_inv = Obj_inv + A_ccs(2) / (1 + r)^(t - year) * sum(sum(I_gen_ccs_2(:, :, year)));
            Obj_inv = Obj_inv + A_ccs(3) / (1 + r)^(t - year) * sum(sum(I_gen_ccs_3(:, :, year)));
            Obj_inv = Obj_inv + A_ccs(4) / (1 + r)^(t - year) * sum(sum(I_gen_ccs_4(:, :, year)));
            %% 燃气机组
            Obj_inv = Obj_inv + A_gas(1) / (1 + r)^(t - year) * sum(sum(I_gen_gas_1(:, :, year)));
            Obj_inv = Obj_inv + A_gas(2) / (1 + r)^(t - year) * sum(sum(I_gen_gas_2(:, :, year)));
            %% 改造
            %Obj_inv = Obj_inv + A_gen_trans(1) / (1 + r)^(t - year) * sum(I_trans_gexist(:,year));
        end
end
display('***机组建设成本 计入 完成！***')
%发电成本
% Obj_u = 0;
% Obj_up = 0;
% Obj_down = 0;

display('***机组发电/碳成本 建模 开始！***')
Cons = [Cons,sum_type_g(:,1,:,:) == sum(g_coal_1,2)];
Cons = [Cons,sum_type_g(:,2,:,:) == sum(g_coal_2,2)];
Cons = [Cons,sum_type_g(:,3,:,:) == sum(g_coal_3,2)];
Cons = [Cons,sum_type_g(:,4,:,:) == sum(g_coal_4,2)];
Cons = [Cons,sum_coal == squeeze(sum(sum(sum_type_g,1),3))];%维度4*years
Cons = [Cons,sum_type_g_ccs(:,1,:,:) == sum(g_ccs_1,2)];
Cons = [Cons,sum_type_g_ccs(:,2,:,:) == sum(g_ccs_2,2)];
Cons = [Cons,sum_type_g_ccs(:,3,:,:) == sum(g_ccs_3,2)];
Cons = [Cons,sum_type_g_ccs(:,4,:,:) == sum(g_ccs_4,2)];
Cons = [Cons,sum_ccs == squeeze(sum(sum(sum_type_g_ccs,1),3))];
Cons = [Cons,sum_type_g_gas(:,1,:,:) == sum(g_gas_1,2)];
Cons = [Cons,sum_type_g_gas(:,2,:,:) == sum(g_gas_2,2)];
Cons = [Cons,sum_gas == squeeze(sum(sum(sum_type_g_gas,1),3))];

Obj_ope_total = 0;
for t = 1:Hours
    for y = 1:Years
            Obj_ope_total = Obj_ope_total + (M * sum(pd_shed(:,t,y)) )*365;%切负荷成本 和 原有机组发电成本
            C_q1(t,y) = K_q * ((P_predict23(t) - g_exist_w1(1, t, y)) + (P_predict27(t) - g_exist_w2(1, t, y))); % 弃风惩罚成本
        for i = 1:length(gen_node)
            node = gen_node(i);
            Obj_ope_total = Obj_ope_total + (1 - I_trans_gexist(i, year))* cost(1).* g_exist_c(node,t,y) + ...
                                             I_trans_gexist(i, year) * cost_ccs(1).* g_exist_c(node,t,y);%原有燃煤机组考虑是否改造后的发电成本
        end
        for i = 1:4
            Obj_ope_total = Obj_ope_total + sum(sum(cost(i).*sum_type_g(:,i,t,y)))*365;%sum_type_g单位：100兆瓦时 cost单位：每100MW费用 总单位就是元
            Obj_ope_total = Obj_ope_total + sum(sum(cost_ccs(i).*sum_type_g_ccs(:,i,t,y)))*365; 
        end
        for i = 1:2
            Obj_ope_total = Obj_ope_total + sum(sum(cost_gas(i).*sum_type_g_gas(:,i,t,y)))*365; 
        end
    end
end     
cost_carbon_coal = sdpvar(4,Years);
cost_carbon_ccs = sdpvar(4,Years);
cost_carbon_gas = sdpvar(2,Years);
cost_carbon_gexist = 0;
for y = 1:Years
    for i = 1:length(gen_node)
        node = gen_node(i);
        cost_carbon_gexist = cost_carbon_gexist + sum(g_exist_c(node,:,y)) * ((1 - I_trans_gexist(i, y))* cei(1)  + ...
                             I_trans_gexist(i, y) * cei_ccs(1) - carbon_quota(1,y)) * carbon_tax(y);%原有燃煤机组考虑是否改造后的碳成本
    end
    for i = 1:4
        quota_value = carbon_quota(min(i, 2), y);  % 当 i=1 时选择第1行，i=2,3,4 时选择第2行
        Cons = [Cons,cost_carbon_coal(i,y) == sum_coal(i, y) * (cei(i) - quota_value) * carbon_tax(y)];%第i种机组第y年的碳成本累加
        Cons = [Cons,cost_carbon_ccs(i,y) == sum_ccs(i, y) * (cei_ccs(i) - quota_value) * carbon_tax(y)];
    end
    for i = 1:2
        Cons = [Cons,cost_carbon_gas(i,y) == sum_gas(i, y) * (cei_gas(i) - carbon_quota_gas(y)) * carbon_tax(y)];
    end
end
Obj_carbon_coal = sum(sum(cost_carbon_coal))* 365;
Obj_carbon_ccs = sum(sum(cost_carbon_ccs))* 365;
Obj_carbon_gas = sum(sum(cost_carbon_gas))* 365;
Obj_carbon =  Obj_carbon_coal + Obj_carbon_ccs + Obj_carbon_gas;
Obj_q = sum(sum(C_q1 * 365));
display('***机组发电/碳成本 计入完成！***')
Obj = Obj_inv + Obj_ope_total + Obj_carbon + Obj_q; %+ Obj_u + Obj_up + Obj_down;
display('***目标函数 表达式 建立完成！***')
% Solve the problem
ops = sdpsettings('verbose',2,'solver','gurobi','gurobi.MIPGap',0.05,'gurobi.Heuristics',0.9,'gurobi.TuneTimeLimit',0);
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
s_x_gen_gas_1 = value(x_gen_gas_1);
s_x_gen_gas_2 = value(x_gen_gas_2);
s_I_lines = value(I_lines);
s_I_gen_coal_1 = value(I_gen_coal_1);
s_I_gen_coal_2 = value(I_gen_coal_2);
s_I_gen_coal_3 = value(I_gen_coal_3);
s_I_gen_coal_4 = value(I_gen_coal_4);
s_I_gen_ccs_1 = value(I_gen_ccs_1);
s_I_gen_ccs_2 = value(I_gen_ccs_2);
s_I_gen_ccs_3 = value(I_gen_ccs_3);
s_I_gen_ccs_4 = value(I_gen_ccs_4);
s_I_gen_gas_1 = value(I_gen_gas_1);
s_I_gen_gas_2 = value(I_gen_gas_2);
s_x_trans_gexist = value(x_trans_gexist);
s_I_trans_gexist = value(I_trans_gexist);
s_x_gens = value(x_gens);
s_x_gens_ccs = value(x_gens_ccs);
s_x_gens_gas = value(x_gens_gas);
s_p = value(p);
s_pd_shed = value(pd_shed);
s_theta = value(theta);
s_g_coal_1 = value(g_coal_1);
s_g_coal_2 = value(g_coal_2);
s_g_coal_3 = value(g_coal_3);
s_g_coal_4 = value(g_coal_4);
s_g_ccs_1 = value(g_ccs_1);
s_g_ccs_2 = value(g_ccs_2);
s_g_ccs_3 = value(g_ccs_3);
s_g_ccs_4 = value(g_ccs_4);
s_sum_N_g = value(sum_N_g);
s_sum_type_g = value(sum_type_g);
s_sum_type_g_ccs = value(sum_type_g_ccs);
s_sum_type_g_gas = value(sum_type_g_gas);
s_sum_coal = value(sum_coal);
s_sum_ccs = value(sum_ccs);
s_sum_gas = value(sum_gas);
s_g_exist = value(g_exist);
s_g_exist_c = value(g_exist_c);
s_g_exist_w1 = value(g_exist_w1);
s_g_exist_w2 = value(g_exist_w2);
s_Obj = value(Obj);
s_Obj_inv = value(Obj_inv);
s_Obj_ope = value(Obj_ope_total);
s_Obj_carbon = value(Obj_carbon);
s_Obj_carbon_coal= value(Obj_carbon_coal);
s_Obj_carbon_ccs= value(Obj_carbon_ccs);
s_Obj_carbon_gas= value(Obj_carbon_gas);
s_Obj_q=value(Obj_q);
Obj_inv_lines = 0;
Obj_inv_coal = 0;
Obj_inv_ccs = 0;
Obj_inv_gas = 0;
%让我们来看看各类机组的建设成本吧！！
for year = 1:Years
    Obj_inv_lines = Obj_inv_lines + sum(c_lines .* x_lines(:,year));
    for i = 1:N
        for t = year:Years
            %常规燃煤机组
            for j = 1:size(x_gen_coal_1, 2)
                Obj_inv_coal = Obj_inv_coal + A_gen(1) * s_I_gen_coal_1(i, j, year) / (1 + r)^(t - year);
            end
            for j = 1:size(x_gen_coal_2, 2)
                Obj_inv_coal = Obj_inv_coal + A_gen(2) * s_I_gen_coal_2(i, j, year) / (1 + r)^(t - year);
            end
            for j = 1:size(x_gen_coal_3, 2)
                Obj_inv_coal = Obj_inv_coal + A_gen(3) * s_I_gen_coal_3(i, j, year) / (1 + r)^(t - year);
            end
            for j = 1:size(x_gen_coal_4, 2)
                Obj_inv_coal = Obj_inv_coal + A_gen(4) * s_I_gen_coal_4(i, j, year) / (1 + r)^(t - year);
            end
            %碳捕集机组
            for j = 1:size(x_gen_coal_1, 2)
                Obj_inv_ccs = Obj_inv_ccs+ A_ccs(1) * s_I_gen_ccs_1(i, j, year) / (1 + r)^(t - year);
            end
            for j = 1:size(x_gen_coal_2, 2)
                Obj_inv_ccs = Obj_inv_ccs + A_ccs(2) * s_I_gen_ccs_2(i, j, year) / (1 + r)^(t - year);
            end
            for j = 1:size(x_gen_coal_3, 2)
                Obj_inv_ccs = Obj_inv_ccs + A_ccs(3) * s_I_gen_ccs_3(i, j, year) / (1 + r)^(t - year);
            end
            for j = 1:size(x_gen_coal_4, 2)
                Obj_inv_ccs = Obj_inv_ccs + A_ccs(4) * s_I_gen_ccs_4(i, j, year) / (1 + r)^(t - year);
            end
            %燃气机组
            for j = 1:size(x_gen_gas_1, 2)
                Obj_inv_gas = Obj_inv_gas + A_gas(1) * s_I_gen_gas_1(i, j, year) / (1 + r)^(t - year);
            end
            for j = 1:size(x_gen_gas_2, 2)
                Obj_inv_gas = Obj_inv_gas + A_gas(2) * s_I_gen_gas_2(i, j, year) / (1 + r)^(t - year);
            end
        end
    end
end
%让我们来看看各类机组的发电成本吧！！
cost_ope = zeros(4,Hours,Years);

for t = 1:Hours
    for y = 1:Years

            cost_ope(1,t,y) = (M * sum(s_pd_shed(:,t,y)) + sum(cost(1).*s_g_exist(:,t,y)))*365;%原有机组发电成本
        for i = 1:4
            cost_ope(2,t,y) = cost_ope(2,t,y) + sum(sum(cost(i).*s_sum_type_g(:,i,t,y)))*365;
            cost_ope(3,t,y) = cost_ope(3,t,y) + sum(sum(cost_ccs(i).*s_sum_type_g_ccs(:,i,t,y)))*365; 
        end
        for i = 1:2
        cost_ope(4,t,y) = cost_ope(2,t,y) + sum(sum(cost_gas(i).*s_sum_type_g_gas(:,i,t,y)))*365; 
        end
    end
end   
Obj_ope_type = squeeze(sum(sum(cost_ope,2),3));
%装机容量
s_total_capacity = zeros(3, Years);
for y = 1:Years
    s_total_capacity(1, y) = sum(sum(s_I_gen_coal_1(:, :, y))) * g_max_all(1) + sum(sum(s_I_gen_coal_2(:, :, y))) * g_max_all(2)+sum(sum(s_I_gen_coal_3(:, :, y))) * g_max_all(3)+sum(sum(s_I_gen_coal_4(:, :, y))) * g_max_all(4);
    s_total_capacity(2, y) = sum(sum(s_I_gen_ccs_1(:, :, y))) * g_max_all(1) + sum(sum(s_I_gen_ccs_2(:, :, y))) * g_max_all(2)+sum(sum(s_I_gen_ccs_3(:, :, y))) * g_max_all(3)+sum(sum(s_I_gen_ccs_4(:, :, y))) * g_max_all(4);
    s_total_capacity(3, y) = sum(sum(s_I_gen_gas_1(:, :, y))) * g_max_gas(1) + sum(sum(s_I_gen_gas_2(:, :, y))) * g_max_gas(2);
end
%发电量
sum_s_sum_coal = sum(s_sum_coal,1);
sum_s_sum_ccs = sum(s_sum_ccs,1);
sum_s_sum_gas = sum(s_sum_gas,1);
%碳成本
carbon_emission_gexist = zeros(length(gen_node),y);
cost_carbon_gexist_years = zeros(length(gen_node),y);
for y = 1:Years
    for i = 1:length(gen_node)
        node = gen_node(i);
        carbon_emission_gexist(i,y) = (sum(s_g_exist_c(node,:,y)) * ((1 - s_I_trans_gexist(i, y))* cei(1)  + s_I_trans_gexist(i, y) * cei_ccs(1)));
        cost_carbon_gexist_years(i,y) = sum(s_g_exist_c(node,:,y)) * ((1 - s_I_trans_gexist(i, y))*cei(1)  + s_I_trans_gexist(i, y)*cei_ccs(1) - carbon_quota(1,y)) * carbon_tax(y);%原有燃煤机组考虑是否改造后
    end
end
%总碳排
carbon_emission_coal = sum(sum(s_sum_coal .* cei'));
carbon_emission_ccs = sum(sum(s_sum_ccs .* cei_ccs'));
carbon_emission_gas = sum(sum(s_sum_gas .* cei_gas'));
carbon_emission = carbon_emission_coal+carbon_emission_ccs+carbon_emission_gas;

Results = zeros(4,4);
Results(1,:) = [sum(sum(sum(s_g_exist_c))),sum(sum_s_sum_coal),sum(sum_s_sum_ccs),sum(sum_s_sum_gas)];%发电量
Results(2,:) = Obj_ope_type';%运行成本
Results(3,:) = [(sum(sum(carbon_emission_gexist))),carbon_emission_coal,carbon_emission_ccs,carbon_emission_gas];%碳排放量
Results(4,:) = [(sum(sum(cost_carbon_gexist_years))),s_Obj_carbon_coal,s_Obj_carbon_ccs,s_Obj_carbon_gas];%碳排放成本
% 定义表头
headers = {'发电量','运行成本','碳排放量','碳排放成本'};
row_headers = {'原有机组','燃煤机组','碳捕集机组','燃气机组'};
% 设置全局显示格式为科学计数法
format shortE;
% 使用 fprintf 函数打印表格
fprintf('%20s %20s %20s %20s %15s\n', '','发电量/100MW','运行成本/元','碳排放量/吨','碳排放成本/元');
for i = 1:4
    fprintf('%20s %20.2e %20.2e %20.2e %20.2e\n', row_headers{i}, Results(1,i), Results(2,i), Results(3,i), Results(4,i));
end

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
set(year1Button, 'Callback', @(src, event) plotResults(1,Hours,Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_sum_type_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E));
set(year2Button, 'Callback', @(src, event) plotResults(4,Hours,Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_sum_type_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E));
set(year3Button, 'Callback', @(src, event) plotResults(7,Hours,Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_sum_type_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E));
set(year4Button, 'Callback', @(src, event) plotResults(10,Hours,Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_sum_type_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E));
set(year5Button, 'Callback', @(src, event) plotResults(13,Hours,Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_sum_type_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E));