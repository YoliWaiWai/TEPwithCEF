%% 一个简单的输电网扩展规划算例示意
% 基于matpower中的30节点网络，case30.m
clear all
close all
clc
define_constants; %打开这个函数可明确mpc的各个矩阵包含的信息，同时参见[1]
% [1]Appendix B Data File Format, MATPWER User s Manual Version 7.1
%2025.1.23：
% 将新建的碳捕集机组用变系数模型表示 总功率和实际碳相关 净输出功率和功率平衡方程相关
% 注意:最大净输出功率变成了容量-碳捕集设备固定能耗，进行容量备用约束时要减去这部分能耗
%2025.3.4
%1.将溶液存储器中贫、富液初始体积设置为决策变量
%2.增加机组启停决策变量和约束（启停时间约束 出力约束）机组启停成本
%3.其他机组参与碳捕集系统供能
%4.改造后的碳捕集机组的电碳也是可调的     
% 未完成：爬坡;溶剂损耗；

%% ***********Parameters **********
Years = 5; % Number of years
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
% 待选节点
gen_nodes_new = [9,11,13,21,22,25,27];
N_new = length(gen_nodes_new); % 新的节点数
M = 1e7;
g_max_all = [300,600,1000,1200]/Sbase;%单位MW
g_max_gas = [180,220]/Sbase;
g_min_all = [0.5,0.5,0.4,0.4] .* g_max_all;
g_max_ccs = g_max_all * 0.9 ;
g_min_ccs = [0.45,0.35,0.30,0.25] .* g_max_all;%碳捕集电厂
g_min_gas = g_max_gas * 0.50;
x_coal_max = [4,5,1,3];%可规划的最大台数
x_gas_max = [4,5];
p_max = mpc.branch(:,RATE_A) * 2.5 / Sbase;%线路传输功率上限为750MW
xb = mpc.branch(:,BR_X); %线路电抗
c_lines = xb*100;  %用线路电抗代表线路长度，得到线路建设成本c_lines
%静态投资成本 单位：亿元
c_gen = [12.9,22,37.5,45]' * 1e8;   % 四种不同类型的燃煤机组静态投资成本/亿元
%c_gen_ccs = 0 * c_gen;
c_gen_ccs = 1.182 * c_gen;        % 新建ccs成本
c_gen_gas = [5.94,6.60]' * 1e8;
c_gen_trans = 0.186 * c_gen;
A_gen = c_gen * annuity_factor;
A_ccs = c_gen_ccs * annuity_factor;
A_gas = c_gen_gas * annuity_factor;
A_gen_trans = c_gen_trans * annuity_factor;
%运行成本
cost =     [0.3171,0.3171,0.2856,0.2856] * 1e5;   % 运行成本 单位：元/kWh   每100MW费用
cost_ccs = 1.59 * cost;   % 运行成本 单位：元/kWh
cost_gas = [0.432,0.396] * 1e5;
K_q = 400;%弃风惩罚成本系数
C_start = [100000,50000,40000,30000];
% 碳排放强度 单位：t/MWh
cei =     [0.905,0.856,0.798,0.794] * 1e2;
cei_ccs = [0.171,0.162,0.145,0.141] * 1e2;
cei_gas = [0.45,0.44] * 1e2;
% 碳排放基准值
% year         1     2    3     4    5    6    7    8    9    10    11    12    13    14    15
carbon_tax =     [100   105   110   115   120   125   130   135   140   145   150   155   160   165   170];         % 碳税﻿ 单位：元/tCO2
% carbon_quota =   [0.7861 0.7822 0.778 0.774 0.770 0.766 0.762 0.758 0.754 0.750 0.746 0.742 0.738 0.734 0.730;%300MW等级以上常规燃煤机组
%                   0.7984 0.7944 0.79  0.786 0.782 0.778 0.774 0.77  0.766 0.762 0.758 0.754 0.75  0.746 0.742]* 1e2;%300MW等级以下常规燃煤机组
carbon_quota  = [0.7,0.7,0.7,0.7,0.7;0.72,0.72,0.72,0.72,0.72]* 1e2;
carbon_quota_gas = [0.3305 0.3288 0.3262 0.3240 0.3185 0.3164 0.3145 0.3128 0.3111 0.3098 0.3087 0.3079 0.3067 0.3055 0.304]* 1e2;%燃煤机组碳排放基准值
Carbon_dioxide_price = 210;%出售二氧化碳价格
%生成一组24h负荷需求数据
pd = mpc.bus(:,PD)/Sbase; %负荷需求标幺值
pd_total = sum(pd);
System_demand = xlsread('gtepuc.xlsx',2,'C3:C26')/Sbase;
E_beta = 0.9; % 碳捕集效率
delta_xz = 1;%烟气分流比限值
P_yita = 1.05; % 再生塔和压缩机最大工作状态系数
% lamda_a = 0.0725;% 吸收单位二氧化碳能耗
% lamda_dc = 0.6525; % 解吸+压缩单位二氧化碳能耗
lamda_a = 0.0725/Sbase;% 吸收单位二氧化碳能耗
lamda_dc = 0.6525/Sbase; % 解吸+压缩单位二氧化碳能耗
M_MEA = 61.08; % M_MEA的摩尔质量
M_co2 = 44; % 二氧化碳的摩尔质量
theta_jx = 0.4; % 再生塔解析量
CR = 40; % 醇胺溶液浓度(%)
rou_R = 1.01; % 醇胺溶液密度
V_CR = 50000; % 溶液储液装置容量
rate_max = 5000 * [1,2,3,4];
K_R = 1.17; % 乙醇胺溶剂成本系数
fai = 1.5; % 溶剂运行损耗系数
K_VE = M_MEA *(M_co2 * theta_jx * CR/100 * rou_R)^(-1);
% 碳捕集设备固定能耗
P_D1 = 10/Sbase;
P_BA_1 = P_D1.* ones(N_new,x_coal_max(1),Hours,Years);
P_BA_2 = P_D1.* ones(N_new,x_coal_max(2),Hours,Years);
P_BA_3 = P_D1.* ones(N_new,x_coal_max(3),Hours,Years);
P_BA_4 = P_D1.* ones(N_new,x_coal_max(4),Hours,Years);
% 风电预测功率
P_predict23 = [320, 250, 310, 270, 340, 280, 150, 140, 200, 190, 110, 70,50, 100, 130, 145, 155, 210, 290, 310, 330, 350, 360, 340]'/Sbase;%该风场容量为400MW
P_predict27 = [339, 287, 449, 471, 512, 530, 527, 441, 434, 319, 201, 334, 389, 330, 512, 505, 206, 85, 81, 80, 83, 110, 353, 523]'/Sbase;%该风场容量为600MW
% 净负荷
NetLoad = System_demand - P_predict23 - P_predict27;
% 30节点24小时负荷数据
P_load(:,:,1)=((System_demand) .* (pd/pd_total)')';%P_load（30*24*6）
% 风功率和系统负荷需求
figure
plot(P_predict23 + P_predict27,'c-<','LineWidth',1.5)
hold on
plot(System_demand,'m-s','LineWidth',1.5)
plot(NetLoad,'r->','LineWidth',1.5)
legend('风电出力','电负荷','净负荷')
xlabel('时间/h');
ylabel('功率/100MW');
title('净负荷初始数据');
growth_rate = (1.06)^3; % 6% growth rate per year
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
T_on_min = 6; % 最小连续开机时间
T_off_min = 6; % 最小连续关停时间
% sale_price = 0.6 * 1e5;
% sale_energy = sum(P_load(:)) * 365 * 5; 
% revenue = sale_price * sale_energy;
%% ***********Variable statement**********
%% 投资决策变量
x_lines = binvar(L,Years);%是否建设线路L

x_gen_coal_1 = binvar(N_new,x_coal_max(1),Years);%在N个节点各建设几台1型燃煤机组
x_gen_coal_2 = binvar(N_new,x_coal_max(2),Years);%在N个节点各建设几台2型燃煤机组
x_gen_coal_3 = binvar(N_new,x_coal_max(3),Years);%在N个节点各建设几台3型燃煤机组
x_gen_coal_4 = binvar(N_new,x_coal_max(4),Years);%在N个节点各建设几台4型燃煤机组

x_gen_ccs_1 = binvar(N_new,x_coal_max(1),Years);%在N个节点各建设几台1型ccs
x_gen_ccs_2 = binvar(N_new,x_coal_max(2),Years);%在N个节点各建设几台2型ccs
x_gen_ccs_3 = binvar(N_new,x_coal_max(3),Years);%在N个节点各建设几台3型ccs
x_gen_ccs_4 = binvar(N_new,x_coal_max(4),Years);%在N个节点各建设几台4型ccs

x_gen_gas_1 = binvar(N_new,x_gas_max(1),Years);%在N个节点各建设几台1型gas
x_gen_gas_2 = binvar(N_new,x_gas_max(2),Years);%在N个节点各建设几台2型gas

x_gens = sdpvar(4,Years);
x_gens_ccs = sdpvar(4,Years);
x_gens_gas = sdpvar(2,Years);

% 投资状态变量
I_lines = binvar(L,Years);%是否已建设线路L
I_gen_coal_1 = binvar(N_new,x_coal_max(1),Years);%在N个节点是否已建设1型燃煤机组
I_gen_coal_2 = binvar(N_new,x_coal_max(2),Years);%在N个节点是否已建设2型燃煤机组
I_gen_coal_3 = binvar(N_new,x_coal_max(3),Years);%在N个节点是否已建设3型燃煤机组
I_gen_coal_4 = binvar(N_new,x_coal_max(4),Years);%在N个节点是否已建设4型燃煤机组
I_gen_ccs_1 = binvar(N_new,x_coal_max(1),Years);
I_gen_ccs_2 = binvar(N_new,x_coal_max(2),Years);
I_gen_ccs_3 = binvar(N_new,x_coal_max(3),Years);
I_gen_ccs_4 = binvar(N_new,x_coal_max(4),Years);
I_gen_gas_1 = binvar(N_new,x_gas_max(1),Years);
I_gen_gas_2 = binvar(N_new,x_gas_max(2),Years);
%% 改造决策变量
% 原有的三台燃煤机组是否改造为碳捕集机组
x_trans_gexist = binvar(3,Years);
I_trans_gexist = binvar(3,Years);
g_trans_net = sdpvar(3,Hours,Years);
g_trans_ccs = sdpvar(3,Hours,Years);
E_trans_ab = sdpvar(3,Hours,Years);
E_trans_de = sdpvar(3,Hours,Years);
E_trans_net = sdpvar(3,Hours,Years);
%% 运行决策变量
theta = sdpvar(N,Hours,Years);
p = sdpvar(L,Hours,Years);
pd_shed = sdpvar(N,Hours,Years);
g_exist = sdpvar(N,Hours,Years);
g_exist_c = sdpvar(N,Hours,Years);
g_exist_w1 = sdpvar(1,Hours,Years);
g_exist_w1_net = sdpvar(1,Hours,Years);
g_exist_w1_ccs = sdpvar(1,Hours,Years);
g_exist_w2 = sdpvar(1,Hours,Years);
g_exist_w2_net = sdpvar(1,Hours,Years);
g_exist_w2_ccs = sdpvar(1,Hours,Years);
g_exist_toccs = sdpvar(N,Hours,Years);
u1 = binvar(N_new,x_coal_max(1),Hours,Years,'full');%节点N的第K台机组在t时段是否运行
u2 = binvar(N_new,x_coal_max(2),Hours,Years,'full');%节点N的第K台机组在t时刻是否运行
u3 = binvar(N_new,x_gas_max(1),Hours,Years,'full');%节点N的第K台机组在t时段是否运行
u4 = binvar(N_new,x_gas_max(2),Hours,Years,'full');%节点N的第K台机组在t时刻是否运行
uccs1 = binvar(N_new,x_coal_max(1),Hours,Years,'full');%节点N的第K台机组在t时段是否运行
uccs2 = binvar(N_new,x_coal_max(2),Hours,Years,'full');%节点N的第K台机组在t时刻是否运行
T_on1 = sdpvar(N_new, x_coal_max(1), Hours, Years, 'full');
T_off1 = sdpvar(N_new, x_coal_max(1), Hours, Years, 'full');
T_on2 = sdpvar(N_new, x_coal_max(2), Hours, Years, 'full');
T_off2 = sdpvar(N_new, x_coal_max(2), Hours, Years, 'full');
T_on3 = sdpvar(N_new, x_gas_max(1), Hours, Years, 'full');
T_off3 = sdpvar(N_new, x_gas_max(1), Hours, Years, 'full');
T_on4 = sdpvar(N_new, x_gas_max(2), Hours, Years, 'full');
T_off4 = sdpvar(N_new, x_gas_max(2), Hours, Years, 'full');
T_onccs1 = sdpvar(N_new, x_coal_max(1), Hours, Years, 'full');
T_offccs1 = sdpvar(N_new, x_coal_max(1), Hours, Years, 'full');
T_onccs2 = sdpvar(N_new, x_coal_max(2), Hours, Years, 'full');
T_offccs2 = sdpvar(N_new, x_coal_max(2), Hours, Years, 'full');
%燃煤机组
g_coal_1 = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');%节点N的第K台机组在t时段的输出功率
g_coal_2 = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
g_coal_3 = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
g_coal_4 = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');

sum_type_g = sdpvar(N_new,length(x_coal_max),Hours,Years,'full');%四种类型一共发了多少
sum_coal = sdpvar(length(x_coal_max),Years);
%% 碳捕集机组运行决策变量
%节点N的第K台机组在t时段的实际功率
g_ccs_1 = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
g_ccs_2 = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
g_ccs_3 = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
g_ccs_4 = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');
g_ccs_1_net = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
g_ccs_2_net = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
g_ccs_3_net = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
g_ccs_4_net = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');
g_ccs_1_ccs = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
g_ccs_2_ccs = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
g_ccs_3_ccs = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
g_ccs_4_ccs = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');
energy_ccs1 = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
energy_ccs2 = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
energy_ccs3 = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
energy_ccs4 = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');
sum_type_g_ccs = sdpvar(N_new,length(x_coal_max),Hours,Years,'full');%四种类型一共发了多少
sum_ccs = sdpvar(length(x_coal_max),Years);
%节点N的第K台机组在t时段的净输出功率
g_ccs_N_1 = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
g_ccs_N_2 = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
g_ccs_N_3 = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
g_ccs_N_4 = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');
% 碳排放量
E_ccs_1 = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
E_ccs_2 = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
E_ccs_3 = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
E_ccs_4 = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');
E_ccs_ab_1 = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
E_ccs_ab_2 = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
E_ccs_ab_3 = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
E_ccs_ab_4 = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');
E_ccs_de_1 = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
E_ccs_de_2 = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
E_ccs_de_3 = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
E_ccs_de_4 = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');
E_ccs_NET_1 = sdpvar(N_new,x_coal_max(1),Hours,Years,'full');
E_ccs_NET_2 = sdpvar(N_new,x_coal_max(2),Hours,Years,'full');
E_ccs_NET_3 = sdpvar(N_new,x_coal_max(3),Hours,Years,'full');
E_ccs_NET_4 = sdpvar(N_new,x_coal_max(4),Hours,Years,'full');

%燃气机组
g_gas_1 = sdpvar(N_new,x_gas_max(1),Hours,Years,'full');%节点N的第K台机组在t时段的输出功率
g_gas_2 = sdpvar(N_new,x_gas_max(2),Hours,Years,'full');

sum_type_g_gas = sdpvar(N_new,length(x_gas_max),Hours,Years,'full');%四种类型一共发了多少
sum_gas = sdpvar(length(x_gas_max),Years);

%% ***********Constraints*************
%% Cons0: 投资状态
display('***开始建立投资状态相关约束！***')
tic
%投资决策变量
Cons = [];
Cons = [Cons,x_gens(1,:) == squeeze(sum(sum(x_gen_coal_1, 2)))'];
Cons = [Cons,x_gens(2,:) == squeeze(sum(sum(x_gen_coal_2, 2)))'];
Cons = [Cons,x_gens(3,:) == squeeze(sum(sum(x_gen_coal_3, 2)))'];
Cons = [Cons,x_gens(4,:) == squeeze(sum(sum(x_gen_coal_4, 2)))'];
Cons = [Cons,x_gens_ccs(1,:) == squeeze(sum(sum(x_gen_ccs_1, 2)))'];
Cons = [Cons,x_gens_ccs(2,:) == squeeze(sum(sum(x_gen_ccs_2, 2)))'];
Cons = [Cons,x_gens_ccs(3,:) == squeeze(sum(sum(x_gen_ccs_3, 2)))'];
Cons = [Cons,x_gens_ccs(4,:) == squeeze(sum(sum(x_gen_ccs_4, 2)))'];
Cons = [Cons,x_gens_gas(1,:) == squeeze(sum(sum(x_gen_gas_1, 2)))'];
Cons = [Cons,x_gens_gas(2,:) == squeeze(sum(sum(x_gen_gas_2, 2)))'];
%机组建设数目上限
 Cons = [Cons, sum(x_gens,2) <= x_coal_max'];
 Cons = [Cons, sum(x_gens_ccs,2) <= x_coal_max'];
 Cons = [Cons, sum(x_gens_gas,2) <= x_gas_max'];
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
toc
% %test 用于测试为什么不建碳捕集电厂 测试完后注释掉这段代码
% Cons = [Cons, I_gen_ccs_1(:,1,3) == 1];
display('***投资状态相关约束 建立完成！***')
%% Cons1: 直流潮流约束+TEP
display('***开始建立 直流潮流约束+TEP 相关约束！***')
tic
sum_N_g = sdpvar(N,Hours,Years); % N个节点的燃煤机组输出功率
sum_N_g_ccs = sdpvar(N,Hours,Years);% N个节点的碳捕集机组【净】输出功率
sum_N_g_ccstoccs = sdpvar(N,Hours,Years);
sum_N_g_gas = sdpvar(N,Hours,Years);% N个节点的燃气机组输出功率
energy_ccs_total = sdpvar(N,Hours,Years);

for y = 1:Years
    for h = 1:Hours
        for i = 1:N_new
            node = gen_nodes_new(i);
            % 各节点燃煤机组上网功率
            Cons = [Cons,sum_N_g(node,h,y) == sum(g_coal_1(i,:,h,y), 2) + sum(g_coal_2(i,:,h,y), 2) + sum(g_coal_3(i,:,h,y), 2) + sum(g_coal_4(i,:,h,y), 2)];%每个节点所有机组在某一时刻的总输出功率的变量
            Cons = [Cons,sum_N_g(setdiff(1:N, gen_nodes_new),h,y) == 0 ];
            % 各节点碳捕集机组上网功率
            Cons = [Cons,sum_N_g_ccs(node,h,y) == sum(g_ccs_1_net(i,:,h,y), 2) + sum(g_ccs_2_net(i,:,h,y), 2) + sum(g_ccs_3_net(i,:,h,y), 2) + sum(g_ccs_4_net(i,:,h,y), 2)];%每个节点所有碳捕集机组在某一时刻的总【净】输出功率的变量
            Cons = [Cons,sum_N_g_ccs(setdiff(1:N, gen_nodes_new),h,y) == 0 ];
            % 各节点碳捕集机组直供碳捕集设备的功率
            Cons = [Cons,sum_N_g_ccstoccs(node,h,y) == sum(g_ccs_1_ccs(i,:,h,y), 2) + sum(g_ccs_2_ccs(i,:,h,y), 2) + sum(g_ccs_3_ccs(i,:,h,y), 2) + sum(g_ccs_4_ccs(i,:,h,y), 2)];
            Cons = [Cons,sum_N_g_ccstoccs(setdiff(1:N, gen_nodes_new),h,y) == 0 ];
            % 各节点燃气机组上网功率
            Cons = [Cons,sum_N_g_gas(node,h,y) == sum(g_gas_1(i,:,h,y), 2) + sum(g_gas_2(i,:,h,y), 2)];%每个节点所有燃气机组在某一时刻的总输出功率的变量
            Cons = [Cons,sum_N_g_gas(setdiff(1:N, gen_nodes_new),h,y) == 0 ];
            % 各节点碳捕集设备功率需求（仅由风机和碳捕集机组提供）
            Cons = [Cons,energy_ccs_total(node,h,y) == sum(energy_ccs1(i,:,h,y), 2)+sum(energy_ccs2(i,:,h,y), 2)+sum(energy_ccs3(i,:,h,y), 2)+sum(energy_ccs4(i,:,h,y), 2)];
            Cons = [Cons,energy_ccs_total(setdiff(1:N, gen_nodes_new),h,y) == 0];
        end
        Cons = [Cons,-(1 - I_lines(:,y)) * M <= In'*theta(:,h,y) - p(:,h,y).* xb];
        Cons = [Cons,In'*theta(:,h,y) - p(:,h,y).* xb <= (1 - I_lines(:,y)) * M];
        Cons = [Cons,In * p(:,h,y) == sum_N_g(:,h,y) + sum_N_g_ccs(:,h,y) + sum_N_g_gas(:,h,y) + g_exist(:,h,y) - (P_load(:,h,y) - pd_shed(:,h,y)) ];
        Cons = [Cons, energy_ccs_total(:,h,y) == g_exist_toccs(:,h,y) + sum_N_g_ccstoccs(:,h,y)];
        Cons = [Cons,theta(1,h,y) == 0];
        Cons = [Cons,- I_lines(:,y) .* p_max <= p(:,h,y)];%线路容量下限
        Cons = [Cons,p(:,h,y) <= I_lines(:,y) .* p_max];%线路容量上限
        Cons = [Cons,P_load(:,h,y) >= pd_shed(:,h,y) >= 0];
    end
end
%下面这个循环是为了保证规划结果便于观测，无物理意义
for j = 2:x_coal_max(1)
    Cons = [Cons, x_gen_coal_1(:,j,:) <= x_gen_coal_1(:,j-1,:)];
    Cons = [Cons, x_gen_ccs_1(:,j,:) <= x_gen_ccs_1(:,j-1,:)];
end
for j = 2:x_coal_max(2)
    Cons = [Cons, x_gen_coal_2(:,j,:) <= x_gen_coal_2(:,j-1,:)];
    Cons = [Cons, x_gen_ccs_2(:,j,:) <= x_gen_ccs_2(:,j-1,:)];
end
for j = 2:x_coal_max(4)
    Cons = [Cons, x_gen_coal_4(:,j,:) <= x_gen_coal_4(:,j-1,:)];
    Cons = [Cons, x_gen_ccs_4(:,j,:) <= x_gen_ccs_4(:,j-1,:)];
end

toc
display('***直流潮流约束+TEP 相关约束 建立完成！***')
%% Cons2: 机组发电功率约束
display('***开始建立 机组发电功率 相关约束！***')
tic
% 原有机组
gen_node = [1,2,22];
gen_c = setdiff(1:N, gen_node);
Cons = [Cons,g_exist_c(gen_c,:,:) == 0];%初始条件
for i = 1:length(gen_node)
    node = gen_node(i);
    for year = 1:Years
% %       改造后用固定运行方式计算：
%         Cons = [Cons, g_min_all(1) * (1 - I_trans_gexist(i, year)) + g_min_ccs(1) * I_trans_gexist(i, year) <= g_exist_c(node, :, year)];
%         Cons = [Cons, g_exist_c(node, :, year) <= g_max_all(1) * (1 - I_trans_gexist(i, year)) + g_max_ccs(1) * I_trans_gexist(i, year)];
%         改造后用可变运行方式计算：
          Cons = [Cons, g_min_all(1) <= g_exist_c(node, :, year) <= g_max_all(1)];
    end
end
% 对于 23 和 27 节点，分别加入风电出力
Cons = [Cons, g_exist_w1_net + g_exist_w1_ccs == g_exist_w1];
Cons = [Cons, g_exist_w2_net + g_exist_w2_ccs == g_exist_w2];
Cons = [Cons, g_exist_w1_net >= 0];
Cons = [Cons, g_exist_w1_ccs >= 0];
Cons = [Cons, g_exist_w2_net >= 0];
Cons = [Cons, g_exist_w2_ccs >= 0];
for y = 1:Years
    for h = 1:Hours
        Cons = [Cons, 0 <= g_exist_w1(1, h, y) <= P_predict23(h)];
        Cons = [Cons, 0 <= g_exist_w2(1, h, y) <= P_predict27(h)];
        Cons = [Cons, g_exist(23, h, y) == g_exist_c(23, h, y) + g_exist_w1_net(1,h,y)];
        Cons = [Cons, g_exist(27, h, y) == g_exist_c(27, h, y) + g_exist_w2_net(1,h,y)];
        Cons = [Cons, g_exist_toccs(23, h, y) ==  g_exist_w1_ccs(1,h,y)];
        Cons = [Cons, g_exist_toccs(27, h, y) ==  g_exist_w2_ccs(1,h,y)];        

        other_nodes = setdiff(1:N, [23, 27]); % 排除23和27节点
        for i = other_nodes
            Cons = [Cons, g_exist(i, h, y) == g_exist_c(i, h, y)];
            Cons = [Cons, g_exist_toccs(i, h, y) ==  0];
        end
    end
end
%% 改造机组
% 改造的碳捕集电厂不从电网获取功率【后续可以区分】
Cons = [Cons, g_trans_net >= 0];
Cons = [Cons, g_trans_ccs >= 0];
Cons = [Cons,E_trans_ab >= 0];
Cons = [Cons,E_trans_de >= 0];
Cons = [Cons,E_trans_net >= 0];
for y =1: Years
    for i = 1:3
        j = gen_node(i);
        Cons = [Cons,g_exist_c(j,:,y) == g_trans_net(i,:,y) + g_trans_ccs(i,:,y)];
        for t = 1:Hours
            Cons = [Cons,g_exist_c(j,t,y) * I_trans_gexist(i,y) >= g_trans_ccs(i,t,y) >= 0];
            Cons = [Cons,squeeze(g_trans_ccs(i,t,y)) ==lamda_a * squeeze(E_trans_ab(i,t,y)) + lamda_dc *  squeeze(E_trans_de(i,t,y)) + 10 * I_trans_gexist(:,:)];
            Cons = [Cons,squeeze(E_trans_ab(i,t,y)) <= (squeeze(g_trans_net(i,t,y) + g_trans_ccs(i,t,y))) * I_trans_gexist(i,y)];
            Cons = [Cons,squeeze(E_trans_ab(i,t,y)) <= rate_max(1) * I_trans_gexist(i,y)];
            Cons = [Cons,squeeze(E_trans_de(i,t,y)) <= rate_max(1) * I_trans_gexist(i,y)];%流速设置为5000
        end
    end
end
Cons = [Cons,E_trans_ab >= 0];
Cons = [Cons,E_trans_de >= 0];
Cons = [Cons,E_trans_net == cei(1) * (g_trans_net + g_trans_ccs) - E_trans_ab];
% 初始平衡
Cons = [Cons,sum(E_trans_ab,2) == sum(E_trans_de,2)];

%% 新增机组
for i=1:N_new
    %Cons = [Cons, u(i,k,t) <= x_gen_coal(i,k)];%运行的机组和投建机组的关系
    %机组发电功率上限 其中1、2型燃煤可以启停
    for t = 1:24
        Cons = [Cons, u1(i,:,t,:) .* g_min_all(1) <= g_coal_1(i,:,t,:)];
        Cons = [Cons, g_coal_1(i,:,t,:) <= u1(i,:,t,:) .* g_max_all(1)];
        Cons = [Cons, u2(i,:,t,:) .* g_min_all(2) <= g_coal_2(i,:,t,:)];
        Cons = [Cons, g_coal_2(i,:,t,:) <= u2(i,:,t,:).* g_max_all(2)];
        Cons = [Cons, I_gen_coal_3(i,:,:) .* g_min_all(3) <= g_coal_3(i,:,t,:)];
        Cons = [Cons, g_coal_3(i,:,t,:) <= I_gen_coal_3(i,:,:) .* g_max_all(3)];
        Cons = [Cons, I_gen_coal_4(i,:,:) .* g_min_all(4) <= g_coal_4(i,:,t,:)];
        Cons = [Cons, g_coal_4(i,:,t,:) <= I_gen_coal_4(i,:,:) .* g_max_all(4)];
        Cons = [Cons, u1(i,:,t,:) <= I_gen_coal_1(i,:,:)];
        Cons = [Cons, u2(i,:,t,:) <= I_gen_coal_2(i,:,:)];
        % 碳捕集电厂【总功率】的上限就是火电机组的上下限
        % 碳捕集电厂总功率 未建设时为0
        Cons = [Cons, uccs1(i,:,t,:) .* g_min_all(1) <= g_ccs_1(i,:,t,:)];
        Cons = [Cons, g_ccs_1(i,:,t,:) <= uccs1(i,:,t,:) .* g_max_all(1)];
        Cons = [Cons, uccs2(i,:,t,:) .* g_min_all(2) <= g_ccs_2(i,:,t,:)];
        Cons = [Cons, g_ccs_2(i,:,t,:) <= uccs2(i,:,t,:) .* g_max_all(2)];
        Cons = [Cons, I_gen_ccs_3(i,:,:) .* g_min_all(3) <= g_ccs_3(i,:,t,:)];
        Cons = [Cons, g_ccs_3(i,:,t,:) <= I_gen_ccs_3(i,:,:) .* g_max_all(3)];
        Cons = [Cons, I_gen_ccs_4(i,:,:) .* g_min_all(4) <= g_ccs_4(i,:,t,:)];
        Cons = [Cons, g_ccs_4(i,:,t,:) <= I_gen_ccs_4(i,:,:) .* g_max_all(4)];
        Cons = [Cons, uccs1(i,:,t,:) <= I_gen_ccs_1(i,:,:)];
        Cons = [Cons, uccs2(i,:,t,:) <= I_gen_ccs_2(i,:,:)];
        % 燃气机组发电功率上限 均可以启停
        Cons = [Cons, u3(i,:,t,:).* g_min_gas(1) <= g_gas_1(i,:,t,:)];
        Cons = [Cons, g_gas_1(i,:,t,:) <= u3(i,:,t,:) .* g_max_gas(1)];
        Cons = [Cons, u4(i,:,t,:).* g_min_gas(2) <= g_gas_2(i,:,t,:)];
        Cons = [Cons, g_gas_2(i,:,t,:) <= u4(i,:,t,:) .* g_max_gas(2)];
        Cons = [Cons, u3(i,:,t,:) <= I_gen_gas_1(i,:,:)];
        Cons = [Cons, u4(i,:,t,:) <= I_gen_gas_2(i,:,:)];
        %烟气分流比限值约束直接写成可吸收的二氧化碳上下限
        % 碳捕集电厂吸收的二氧化碳量Eab 未运行时为0
        Cons = [Cons, E_beta * (1 - delta_xz ) * uccs1(i,:,t,:).* E_ccs_1(i,:,t,:) <= E_ccs_ab_1(i,:,t,:)];
        Cons = [Cons, E_ccs_ab_1(i,:,t,:) <= E_beta * delta_xz * uccs1(i,:,t,:).* E_ccs_1(i,:,t,:)]; 
        Cons = [Cons, E_beta * (1 - delta_xz ) * uccs2(i,:,t,:).* E_ccs_2(i,:,t,:) <= E_ccs_ab_2(i,:,t,:)];
        Cons = [Cons, E_ccs_ab_2(i,:,t,:) <= E_beta * delta_xz * uccs2(i,:,t,:).* E_ccs_2(i,:,t,:)];
        Cons = [Cons, E_beta * (1 - delta_xz ) * I_gen_ccs_3(i,:,:).* E_ccs_3(i,:,t,:) <= E_ccs_ab_3(i,:,t,:)];
        Cons = [Cons, E_ccs_ab_3(i,:,t,:) <= E_beta * delta_xz * I_gen_ccs_3(i,:,:).* E_ccs_3(i,:,t,:)];
        Cons = [Cons, E_beta * (1 - delta_xz ) * I_gen_ccs_4(i,:,:).* E_ccs_4(i,:,t,:) <= E_ccs_ab_4(i,:,t,:)];
        Cons = [Cons, E_ccs_ab_4(i,:,t,:) <= E_beta * delta_xz * I_gen_ccs_4(i,:,:).*E_ccs_4(i,:,t,:)];
%         % 碳捕集机组能量和二氧化碳流动关系
        Cons = [Cons,energy_ccs1(i,:,t,:) == lamda_a * E_ccs_ab_1(i,:,t,:) + lamda_dc *  E_ccs_de_1(i,:,t,:) + reshape(P_D1*I_gen_ccs_1(i,:,:), [1, 4, 1, 5])];
        Cons = [Cons,energy_ccs2(i,:,t,:) == lamda_a * E_ccs_ab_2(i,:,t,:) + lamda_dc *  E_ccs_de_2(i,:,t,:) + reshape(P_D1*I_gen_ccs_2(i,:,:), [1, 5, 1, 5])];
        Cons = [Cons,energy_ccs3(i,:,t,:) == lamda_a * E_ccs_ab_3(i,:,t,:) + lamda_dc *  E_ccs_de_3(i,:,t,:) + reshape(P_D1*I_gen_ccs_3(i,:,:), [1, 1, 1, 5])];
        Cons = [Cons,energy_ccs4(i,:,t,:) == lamda_a * E_ccs_ab_4(i,:,t,:) + lamda_dc *  E_ccs_de_4(i,:,t,:) + reshape(P_D1*I_gen_ccs_4(i,:,:), [1, 3, 1, 5])];
    end
end

for n = 1:N_new
    for y = 1:Years
        for k = 1:x_gas_max(1)
            % 计算每天的总开机时间
            Cons = [Cons, sum(u3(n, k, :, y)) >= 9 * I_gen_gas_1(n, k, y)];
        end
        for k = 1:x_gas_max(2)
            % 添加约束：每天总开机时间不少于9小时
            Cons = [Cons, sum(u4(n, k, :, y)) >= 9 * I_gen_gas_2(n, k, y)];
        end
    end
end

Cons = [Cons,g_ccs_1 == g_ccs_1_net + g_ccs_1_ccs];
Cons = [Cons,g_ccs_2 == g_ccs_2_net + g_ccs_2_ccs];
Cons = [Cons,g_ccs_3 == g_ccs_3_net + g_ccs_3_ccs];
Cons = [Cons,g_ccs_4 == g_ccs_4_net + g_ccs_4_ccs];
Cons = [Cons,g_ccs_1_net >= 0];
Cons = [Cons,g_ccs_2_net >= 0];
Cons = [Cons,g_ccs_3_net >= 0];
Cons = [Cons,g_ccs_4_net >= 0];
Cons = [Cons,g_ccs_1_ccs >= 0];
Cons = [Cons,g_ccs_2_ccs >= 0];
Cons = [Cons,g_ccs_3_ccs >= 0];
Cons = [Cons,g_ccs_4_ccs >= 0];

% 碳捕集机组产生的总碳排放
% 当前代码可以保证未建设时总碳排也为零
Cons = [Cons,E_ccs_1 == cei(1) * g_ccs_1];
Cons = [Cons,E_ccs_2 == cei(2) * g_ccs_2];
Cons = [Cons,E_ccs_3 == cei(3) * g_ccs_3];
Cons = [Cons,E_ccs_4 == cei(4) * g_ccs_4];

% 当前代码可以保证未建设时净碳排也为零
Cons = [Cons,E_ccs_NET_1 == E_ccs_1 - E_ccs_ab_1]; % 净碳排
Cons = [Cons,E_ccs_NET_2 == E_ccs_2 - E_ccs_ab_2];
Cons = [Cons,E_ccs_NET_3 == E_ccs_3 - E_ccs_ab_3];
Cons = [Cons,E_ccs_NET_4 == E_ccs_4 - E_ccs_ab_4];

toc
display('*** 机组发电功率 相关约束 建立完成！***')

%% Cons3: 碳捕集装置约束
display('***开始建立 碳捕集装置 相关约束！***')
tic
% 每天吸收的总量和解吸的总量相同，满足贫富液初始平衡
Cons = [Cons,sum(E_ccs_ab_1,3) == sum(E_ccs_de_1,3)];
Cons = [Cons,sum(E_ccs_ab_2,3) == sum(E_ccs_de_2,3)];
Cons = [Cons,sum(E_ccs_ab_3,3) == sum(E_ccs_de_3,3)];
Cons = [Cons,sum(E_ccs_ab_4,3) == sum(E_ccs_de_4,3)];
Cons = [Cons,E_ccs_ab_1 >= 0];
Cons = [Cons,E_ccs_ab_2 >= 0];
Cons = [Cons,E_ccs_ab_3 >= 0];
Cons = [Cons,E_ccs_ab_4 >= 0];
Cons = [Cons,E_ccs_de_1 >= 0];
Cons = [Cons,E_ccs_de_2 >= 0];
Cons = [Cons,E_ccs_de_3 >= 0];
Cons = [Cons,E_ccs_de_4 >= 0];
for t= 1:Hours
    Cons = [Cons,E_ccs_ab_1(:,:,t,:) <= rate_max(1) * I_gen_ccs_1(:,:,:)];
    Cons = [Cons,E_ccs_ab_2(:,:,t,:) <= rate_max(2) * I_gen_ccs_2(:,:,:)];
    Cons = [Cons,E_ccs_ab_3(:,:,t,:) <= rate_max(3) * I_gen_ccs_3(:,:,:)];
    Cons = [Cons,E_ccs_ab_4(:,:,t,:) <= rate_max(4) * I_gen_ccs_4(:,:,:)];
    Cons = [Cons,E_ccs_de_1(:,:,t,:) <= rate_max(1) * I_gen_ccs_1(:,:,:)];
    Cons = [Cons,E_ccs_de_2(:,:,t,:) <= rate_max(2) * I_gen_ccs_2(:,:,:)];
    Cons = [Cons,E_ccs_de_3(:,:,t,:) <= rate_max(3) * I_gen_ccs_3(:,:,:)];
    Cons = [Cons,E_ccs_de_4(:,:,t,:) <= rate_max(4) * I_gen_ccs_4(:,:,:)];
end
toc
display('*** 碳捕集装置 相关约束 建立完成！***')

%% Cons4: 系统日电力备用约束
display('***开始建立 Cons3: 系统日电力备用约束！***')
tic
total_capacity_yearly = sdpvar(1,Years);
total_coal_ccs_capacity_y= sdpvar(1,Years);
total_gas_capacity_y= sdpvar(1,Years);
for y = 1:Years
    % 计算每年的总容量
    Cons = [Cons,total_coal_ccs_capacity_y(y) == sum(sum(I_gen_coal_1(:,:,y),2)).*g_max_all(1) + sum(g_max_all(1) * (1 - I_trans_gexist(:,y)) + (g_max_all(1)-P_D1) * I_trans_gexist(:,y))+...
        sum(sum(I_gen_coal_2(:,:,y),2)).*g_max_all(2) + ...
        sum(sum(I_gen_coal_3(:,:,y),2)).*g_max_all(3) + ...
        sum(sum(I_gen_coal_4(:,:,y),2)).*g_max_all(4) + ...
        sum(sum(I_gen_ccs_1(:,:,y),2)).*(g_max_all(1)-P_D1) + ...
        sum(sum(I_gen_ccs_2(:,:,y),2)).*(g_max_all(2)-P_D1) + ...
        sum(sum(I_gen_ccs_3(:,:,y),2)).*(g_max_all(3)-P_D1) + ...
        sum(sum(I_gen_ccs_4(:,:,y),2)).*(g_max_all(4)-P_D1)];

    Cons = [Cons,total_gas_capacity_y(y) == sum(sum(I_gen_gas_1(:,:,y),2)).*g_max_gas(1) + sum(sum(I_gen_gas_2(:,:,y),2)).*g_max_gas(2)];

    Cons = [Cons,total_capacity_yearly(y) == total_coal_ccs_capacity_y(y) + total_gas_capacity_y(y)];


    % 系统容量备用约束
    Cons = [Cons, total_capacity_yearly(y) >= (1 + r_u) * P_load_max(y)];
end
toc
display('*** 系统日电力备用约束 建立完成！***')
display('*** 开始建立 机组启停约束！***')
tic
for t = 2:Hours
    % 更新连续开机与关停时间
    Cons = [Cons, T_on1(:, :, t, :) == T_on1(:, :, t-1, :) + u1(:, :, t-1, :)];
    Cons = [Cons, T_off1(:, :, t, :) == T_off1(:, :, t-1, :) + (1 - u1(:, :, t-1, :))];
    % 启停约束
    Cons = [Cons, (T_on1(:, :, t-1, :) - T_on_min) .* (u1(:, :, t-1, :) - u1(:, :, t, :)) >= 0];
    Cons = [Cons, (T_off1(:, :, t-1, :) - T_off_min) .*  (u1(:, :, t, :) - u1(:, :, t-1, :)) >= 0];
    % 更新连续开机与关停时间
    Cons = [Cons, T_on2(:, :, t, :) == T_on2(:, :, t-1, :) + u2(:, :, t-1, :)];
    Cons = [Cons, T_off2(:, :, t, :) == T_off2(:, :, t-1, :) + (1 - u2(:, :, t-1, :))];
    % 启停约束
    Cons = [Cons, (T_on2(:, :, t-1, :) - T_on_min) .*  (u2(:, :, t-1, :) - u2(:, :, t, :)) >= 0];
    Cons = [Cons, (T_off2(:, :, t-1, :) - T_off_min) .* (u2(:, :, t, :) - u2(:, :, t-1, :)) >= 0];
    % 更新连续开机与关停时间
    Cons = [Cons, T_on3(:, :, t, :) == T_on3(:, :, t-1, :) + u3(:, :, t-1, :)];
    Cons = [Cons, T_off3(:, :, t, :) == T_off3(:, :, t-1, :) + (1 - u3(:, :, t-1, :))];
    % 启停约束
    Cons = [Cons, (T_on3(:, :, t-1, :) - T_on_min) .*  (u3(:, :, t-1, :) - u3(:, :, t, :)) >= 0];
    Cons = [Cons, (T_off3(:, :, t-1, :) - T_off_min) .*  (u3(:, :, t, :) - u3(:, :, t-1, :)) >= 0];
    % 更新连续开机与关停时间
    Cons = [Cons, T_on4(:, :, t, :) == T_on4(:, :, t-1, :) + u4(:, :, t-1, :)];
    Cons = [Cons, T_off4(:, :, t, :) == T_off4(:, :, t-1, :) + (1 - u4(:, :, t-1, :))];
    % 启停约束
    Cons = [Cons, (T_on4(:, :, t-1, :) - T_on_min) .*  (u4(:, :, t-1, :) - u4(:, :, t, :)) >= 0];
    Cons = [Cons, (T_off4(:, :, t-1, :) - T_off_min) .*  (u4(:, :, t, :) - u4(:, :, t-1, :)) >= 0];
    % 更新连续开机与关停时间
    Cons = [Cons, T_onccs1(:, :, t, :) == T_onccs1(:, :, t-1, :) + uccs1(:, :, t-1, :)];
    Cons = [Cons, T_offccs1(:, :, t, :) == T_offccs1(:, :, t-1, :) + (1 - uccs1(:, :, t-1, :))];
    % 启停约束
    Cons = [Cons, (T_onccs1(:, :, t-1, :) - T_on_min) .*  (uccs1(:, :, t-1, :) - uccs1(:, :, t, :)) >= 0];
    Cons = [Cons, (T_offccs1(:, :, t-1, :) - T_off_min) .*  (uccs1(:, :, t, :) - uccs1(:, :, t-1, :)) >= 0];
    % 更新连续开机与关停时间
    Cons = [Cons, T_onccs2(:, :, t, :) == T_onccs2(:, :, t-1, :) + uccs2(:, :, t-1, :)];
    Cons = [Cons, T_offccs2(:, :, t, :) == T_offccs2(:, :, t-1, :) + (1 - uccs2(:, :, t-1, :))];
    % 启停约束
    Cons = [Cons, (T_onccs2(:, :, t-1, :) - T_on_min) .*  (uccs2(:, :, t-1, :) - uccs2(:, :, t, :)) >= 0];
    Cons = [Cons, (T_offccs2(:, :, t-1, :) - T_off_min) .*  (uccs2(:, :, t, :) - uccs2(:, :, t-1, :)) >= 0];
end
toc
display('*** 机组启停 建立完成！***')
%% Obj: 计算投资成本
display('***开始建立 目标函数 表达式！***')
tic
Obj_inv_line = 0;
Obj_inv_coal = 0;
Obj_inv_ccs = 0;
Obj_inv_gas = 0;
Obj_inv_trans = 0;
for year = 1:Years
    Obj_inv_line = Obj_inv_line + sum(c_lines .* x_lines(:,year));
    for t = year:Years
        %% 常规燃煤机组
        Obj_inv_coal = Obj_inv_coal + A_gen(1) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_coal_1(:, :, year)));
        Obj_inv_coal = Obj_inv_coal + A_gen(2) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_coal_2(:, :, year)));
        Obj_inv_coal = Obj_inv_coal + A_gen(3) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_coal_3(:, :, year)));
        Obj_inv_coal = Obj_inv_coal + A_gen(4) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_coal_4(:, :, year)));
        %% 碳捕集机组
        Obj_inv_ccs = Obj_inv_ccs + A_ccs(1) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_ccs_1(:, :, year)));
        Obj_inv_ccs = Obj_inv_ccs + A_ccs(2) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_ccs_2(:, :, year)));
        Obj_inv_ccs = Obj_inv_ccs + A_ccs(3) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_ccs_3(:, :, year)));
        Obj_inv_ccs = Obj_inv_ccs + A_ccs(4) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_ccs_4(:, :, year)));
        %% 燃气机组
        Obj_inv_gas = Obj_inv_gas + A_gas(1) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_gas_1(:, :, year)));
        Obj_inv_gas = Obj_inv_gas + A_gas(2) / (1 + r)^((t - year) * 3) * sum(sum(x_gen_gas_2(:, :, year)));
        %% 改造
        Obj_inv_trans = Obj_inv_trans + A_gen_trans(1) / (1 + r)^((t - year) * 3) * sum(x_trans_gexist(:,year));
    end
end
Obj_inv = Obj_inv_line+Obj_inv_coal+Obj_inv_ccs+Obj_inv_gas+Obj_inv_trans;
toc
display('***机组建设成本 计入 完成！***')

display('***机组发电/碳成本 建模 开始！***')
display('**Part I 开始**')
tic
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
toc
display('**Part I 结束**')

display('**Part II 开始**')
tic
Obj_ope_total = 0;
Obj_ope_shed = 0;
for t = 1:Hours
    for y = 1:Years
        Obj_ope_shed = Obj_ope_shed + (M * sum(pd_shed(:,t,y)) )*365*3;%切负荷成本 和 原有机组发电成本
        C_q1(t,y) = K_q * ((P_predict23(t) - g_exist_w1(1, t, y)) + (P_predict27(t) - g_exist_w2(1, t, y))); % 弃风惩罚成本
        for i = 1:length(gen_node)
            node = gen_node(i);
            Obj_ope_total = Obj_ope_total + (1 - I_trans_gexist(i, year))* cost(1).* g_exist_c(node,t,y)*365*3 + ...
                I_trans_gexist(i, year) * cost(1).* g_exist_c(node,t,y)*365*3;%原有燃煤机组考虑是否改造后的发电成本
        end
        for i = 1:4
            Obj_ope_total = Obj_ope_total + sum(sum(cost(i).*sum_type_g(:,i,t,y)))*365*3;%sum_type_g单位：100兆瓦时 cost单位：每100MW费用 总单位就是元
            Obj_ope_total = Obj_ope_total + sum(sum(cost(i).*sum_type_g_ccs(:,i,t,y)))*365*3;
        end
        for i = 1:2
            Obj_ope_total = Obj_ope_total + sum(sum(cost_gas(i).*sum_type_g_gas(:,i,t,y)))*365*3;
        end
    end
end

%启停成本
 for t = 2:24
     C_qiting(1)= sum(sum(sum(u1(:,:,t,:) .* (1 - u1(:,:,t-1,:)) + u1(:,:,t-1,:) .* (1 - u1(:,:,t,:))))) * C_start(1);%燃煤1启停
     C_qiting(2)= sum(sum(sum(u2(:,:,t,:) .* (1 - u2(:,:,t-1,:)) + u2(:,:,t-1,:) .* (1 - u2(:,:,t,:))))) * C_start(2);%燃煤2启停
     C_qiting(3)= sum(sum(sum(u3(:,:,t,:) .* (1 - u3(:,:,t-1,:)) + u3(:,:,t-1,:) .* (1 - u3(:,:,t,:))))) * C_start(3);%燃气1启停
     C_qiting(4)= sum(sum(sum(u4(:,:,t,:) .* (1 - u4(:,:,t-1,:)) + u4(:,:,t-1,:) .* (1 - u4(:,:,t,:))))) * C_start(4);%燃气2启停
     C_qiting(5)= sum(sum(sum(uccs1(:,:,t,:) .* (1 - uccs1(:,:,t-1,:)) + uccs1(:,:,t-1,:) .* (1 - uccs1(:,:,t,:))))) * C_start(1);%燃煤1启停
     C_qiting(6)= sum(sum(sum(uccs2(:,:,t,:) .* (1 - uccs2(:,:,t-1,:)) + uccs2(:,:,t-1,:) .* (1 - u2(:,:,t,:))))) * C_start(2);%燃煤2启停
 end
Obj_C_qiting = sum(C_qiting)*365*3;
toc
display('**Part II 结束**')

display('**Part III 开始**')
tic
cost_carbon_coal = sdpvar(4,Years);
cost_carbon_ccs = sdpvar(4,Years);
cost_carbon_gas = sdpvar(2,Years);
cost_carbon_gexist = sdpvar(3,Years);
sale_trans = sdpvar(3,Years);
for y = 1:Years
    %     固定运行方式的碳成本这么计算：
    %     for i = 1:length(gen_node)
    %         node = gen_node(i);
    %         cost_carbon_gexist = cost_carbon_gexist + sum(g_exist_c(node,:,y)) * carbon_tax(y) * 365 * 5;%原有燃煤机组考虑是否改造后的碳成本
    %         sale_trans = sale_trans + sum(g_exist_c(node,:,y)) * I_trans_gexist(i, y) *(cei(1)-cei_ccs(1))* Carbon_dioxide_price * 365 * 5;
    %     end
    %     灵活运行方式的碳成本这么计算：
    for i =1:3
        Cons = [Cons,cost_carbon_gexist(i,y) ==  sum((cei(1) -  carbon_quota(2,y)) * (g_trans_ccs(i,:,y) + g_trans_net(i,:,y)) - E_trans_ab(i,:,y))];
        Cons = [Cons,sale_trans(i,y) ==  sum(E_trans_de(i,:,y)) * Carbon_dioxide_price];
    end
    for i = 1:4
        quota_value = carbon_quota(min(i, 2), y);  % 当 i=1 时选择第1行，i=2,3,4 时选择第2行
        Cons = [Cons,cost_carbon_coal(i,y) == sum_coal(i, y) * (cei(i) - quota_value) * carbon_tax(y)];%第i种机组第y年的碳成本累加
    end
    Cons = [Cons,cost_carbon_ccs(1,y) == sum(sum(sum((E_ccs_NET_1(:,:,:,y) - carbon_quota(1,y) * g_ccs_1(:,:,:,y))))) * carbon_tax(y)];
    Cons = [Cons,cost_carbon_ccs(2,y) == sum(sum(sum((E_ccs_NET_2(:,:,:,y) - carbon_quota(2,y) * g_ccs_2(:,:,:,y))))) * carbon_tax(y)];
    Cons = [Cons,cost_carbon_ccs(3,y) == sum(sum(sum((E_ccs_NET_3(:,:,:,y) - carbon_quota(2,y) * g_ccs_3(:,:,:,y))))) * carbon_tax(y)];
    Cons = [Cons,cost_carbon_ccs(4,y) == sum(sum(sum((E_ccs_NET_4(:,:,:,y) - carbon_quota(2,y) * g_ccs_4(:,:,:,y))))) * carbon_tax(y)];
    for i = 1:2
        Cons = [Cons,cost_carbon_gas(i,y) == sum_gas(i, y) * (cei_gas(i) - carbon_quota_gas(y)) * carbon_tax(y)];
    end
end
Obj_carbon_coal = sum(sum(cost_carbon_coal))* 365*3;
Obj_carbon_ccs = sum(sum(cost_carbon_ccs))* 365*3;
Obj_carbon_gas = sum(sum(cost_carbon_gas))* 365*3;
Obj_carbon_gexist = sum(sum(cost_carbon_gexist))* 365*3;
Obj_q = sum(sum(C_q1 * 365*3));%弃风惩罚成本
Obj_carbon =  Obj_carbon_coal + Obj_carbon_ccs + Obj_carbon_gas + Obj_carbon_gexist;%碳交易成本
% 售碳成本
sale_ccs = sdpvar(4,Years);
for y = 1:Years
    Cons = [Cons,sale_ccs(1,y) == sum(sum(sum(E_ccs_de_1(:,:,:,y))))* Carbon_dioxide_price];
    Cons = [Cons,sale_ccs(2,y) == sum(sum(sum(E_ccs_de_2(:,:,:,y))))* Carbon_dioxide_price];
    Cons = [Cons,sale_ccs(3,y) == sum(sum(sum(E_ccs_de_3(:,:,:,y))))* Carbon_dioxide_price];
    Cons = [Cons,sale_ccs(4,y) == sum(sum(sum(E_ccs_de_4(:,:,:,y))))* Carbon_dioxide_price];
end
Obj_sale = sum(sum(sale_ccs))+sum(sum(sale_trans))*365*3;
toc
display('**Part III 结束**')
display('***机组发电/碳成本 计入完成！***')
 Obj = Obj_inv + Obj_ope_total + Obj_carbon + Obj_q + Obj_C_qiting - Obj_sale; 
%Obj = 0;
display('***目标函数 表达式 建立完成！***')
% Solve the problem
ops = sdpsettings('verbose',2,'solver','gurobi','gurobi.MIPGap',0.09,'gurobi.Heuristics',0.9,'gurobi.TuneTimeLimit',0);
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
s_sum_N_g = value(sum_N_g);
s_sum_N_g_ccs = value(sum_N_g_ccs);
s_sum_N_g_gas = value(sum_N_g_gas);
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
s_Obj_inv_line = value(Obj_inv_line);
s_Obj_inv_coal = value(Obj_inv_coal);
s_Obj_inv_ccs = value(Obj_inv_ccs);
s_Obj_inv_gas = value(Obj_inv_gas);
s_Obj_inv_trans = value(Obj_inv_trans);
s_Obj_ope = value(Obj_ope_total);
s_Obj_carbon = value(Obj_carbon);
s_Obj_carbon_coal= value(Obj_carbon_coal);
s_Obj_carbon_ccs= value(Obj_carbon_ccs);
s_Obj_carbon_gas= value(Obj_carbon_gas);
s_Obj_q=value(Obj_q);
s_Obj_sale = value(Obj_sale);
s_sale_ccs = value(sale_ccs);
s_sale_trans = value(sale_trans);
s_E_ccs_NET_1 = value(E_ccs_NET_1);
s_E_ccs_NET_2 = value(E_ccs_NET_2);
s_E_ccs_NET_3 = value(E_ccs_NET_3);
s_E_ccs_NET_4 = value(E_ccs_NET_4);
s_E_ccs_de_1 = value(E_ccs_de_1);
s_E_ccs_de_2 = value(E_ccs_de_2);
s_E_ccs_de_3 = value(E_ccs_de_3);
s_E_ccs_de_4 = value(E_ccs_de_4);
s_energy_ccs1 = value(energy_ccs1);
s_energy_ccs2 = value(energy_ccs2);
s_energy_ccs3 = value(energy_ccs3);
s_energy_ccs4 = value(energy_ccs4);

%装机容量
s_total_capacity = zeros(3, Years);
for y = 1:Years
    s_total_capacity(1, y) = sum(sum(s_I_gen_coal_1(:, :, y))) * g_max_all(1) + sum(sum(s_I_gen_coal_2(:, :, y))) * g_max_all(2)+sum(sum(s_I_gen_coal_3(:, :, y))) * g_max_all(3)+sum(sum(s_I_gen_coal_4(:, :, y))) * g_max_all(4);
    s_total_capacity(2, y) = sum(sum(s_I_gen_ccs_1(:, :, y))) * g_max_all(1) + sum(sum(s_I_gen_ccs_2(:, :, y))) * g_max_all(2)+sum(sum(s_I_gen_ccs_3(:, :, y))) * g_max_all(3)+sum(sum(s_I_gen_ccs_4(:, :, y))) * g_max_all(4);
    s_total_capacity(3, y) = sum(sum(s_I_gen_gas_1(:, :, y))) * g_max_gas(1) + sum(sum(s_I_gen_gas_2(:, :, y))) * g_max_gas(2);
end

% 发电成本
cost_ope = zeros(4,Hours,Years);
for t = 1:Hours
    for y = 1:Years
        cost_ope(1,t,y) = sum(cost(1).*s_g_exist(:,t,y))*365*5;%原有机组发电成本
        for i = 1:4
            cost_ope(2,t,y) = cost_ope(2,t,y) + sum(sum(cost(i).*s_sum_type_g(:,i,t,y)))*365*3;
            cost_ope(3,t,y) = cost_ope(3,t,y) + sum(sum(cost_ccs(i).*s_sum_type_g_ccs(:,i,t,y)))*365*3;
        end
        for i = 1:2
            cost_ope(4,t,y) = cost_ope(4,t,y) + sum(sum(cost_gas(i).*s_sum_type_g_gas(:,i,t,y)))*365*3;
        end
    end
end
Obj_ope_type = squeeze(sum(sum(cost_ope,2),3));

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
        carbon_emission_gexist(i,y) = (sum(s_g_exist_c(node,:,y)) * ((1 - s_I_trans_gexist(i, y))* cei(1)  + s_I_trans_gexist(i, y) * cei_ccs(1)))*365*3;
        cost_carbon_gexist_years(i,y) = sum(s_g_exist_c(node,:,y)) * ((1 - s_I_trans_gexist(i, y))*cei(1)  + s_I_trans_gexist(i, y) * cei_ccs(1) - carbon_quota(1,y)) * carbon_tax(y)*365*3;%原有燃煤机组考虑是否改造后
    end
end
%总碳排
carbon_emission_coal = sum(sum(s_sum_coal .* cei'))*365*3;
carbon_emission_ccs = sum(sum(sum(sum(s_E_ccs_NET_1,2)+sum(s_E_ccs_NET_2,2)+sum(s_E_ccs_NET_3,2)+sum(s_E_ccs_NET_4,2))))*365*3;
carbon_emission_gas = sum(sum(s_sum_gas .* cei_gas'))*365*3;
carbon_emission = carbon_emission_coal+carbon_emission_ccs+carbon_emission_gas;

Results = zeros(5,4);
Results(1,:) = [9,s_total_capacity(1,5),s_total_capacity(2,5),s_total_capacity(3,5)];
Results(2,:) = [sum(sum(sum(s_g_exist_c))),sum(sum_s_sum_coal),sum(sum_s_sum_ccs),sum(sum_s_sum_gas)];%发电量
Results(3,:) = Obj_ope_type';%运行成本
Results(4,:) = [(sum(sum(carbon_emission_gexist))),carbon_emission_coal,carbon_emission_ccs,carbon_emission_gas];%碳排放量
Results(5,:) = [(sum(sum(cost_carbon_gexist_years))),s_Obj_carbon_coal,s_Obj_carbon_ccs,s_Obj_carbon_gas];%碳排放成本
% 定义表头
headers = {'装机容量','发电量','运行成本','碳排放量','碳排放成本'};
row_headers = {'原有常规机组','新建燃煤机组','新建碳捕集机组','新建燃气机组'};
% 设置全局显示格式为科学计数法
format shortE;
% 使用 fprintf 函数打印表格
fprintf('%40s %20s  %15s %20s %15s\n', '装机容量/100MW','发电量/100MWh','运行成本/元','碳排放量/吨','碳排放成本/元');
for i = 1:4
    fprintf('%20s %20.2e %20.2e %20.2e %20.2e %20.2e\n', row_headers{i}, Results(1,i), Results(2,i), Results(3,i), Results(4,i), Results(5,i));
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
set(year1Button, 'Callback', @(src, event) plotResults(1,Hours,cost_ope,s_sum_N_g,s_sum_N_g_ccs,s_sum_N_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E,N_new,gen_nodes_new));
set(year2Button, 'Callback', @(src, event) plotResults(2,Hours,cost_ope,s_sum_N_g,s_sum_N_g_ccs,s_sum_N_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E,N_new,gen_nodes_new));
set(year3Button, 'Callback', @(src, event) plotResults(3,Hours,cost_ope,s_sum_N_g,s_sum_N_g_ccs,s_sum_N_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E,N_new,gen_nodes_new));
set(year4Button, 'Callback', @(src, event) plotResults(4,Hours,cost_ope,s_sum_N_g,s_sum_N_g_ccs,s_sum_N_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E,N_new,gen_nodes_new));
set(year5Button, 'Callback', @(src, event) plotResults(5,Hours,cost_ope,s_sum_N_g,s_sum_N_g_ccs,s_sum_N_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,I,J,l_E,N_new,gen_nodes_new));