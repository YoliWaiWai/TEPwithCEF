%%  日前调度
clc
clear
close all
%% 数据导入 
% 调度周期
T = 24;
% 风电预测功率
P_predict = 1.1*[320, 250, 310, 270, 340, 280, 150, 140, 200, 190, 110, 70,... 
                50, 100, 130, 145, 155, 210, 290, 310, 330, 350, 360, 340];
% 电负荷
EleLoad = 0.3*[950,820,780,750,800,1100,1650,1850,1950,1800,1700,1650,1550,1450,1350,1250,1450,1800,2100,1900,1750,1600,1350,1100];
% 净负荷
NetLoad = EleLoad - P_predict;
% 原始数据
figure
plot(P_predict,'c-<','LineWidth',1.5)
hold on
plot(EleLoad,'m-s','LineWidth',1.5)
% plot(NetLoad,'r->','LineWidth',1.5)
legend('风电出力','负荷需求')
xlabel('时间/h');
ylabel('功率/kW');
%% 相关参数
cost = 300;
C_start = 31500; % 启停成本
eg = 0.82; % 火电机组i的碳排放强度 单位：t/（MW·h）
E_beta = 0.9; % 碳捕集效率
P_yita = 1.05; % 再生塔和压缩机最大工作状态系数
lamda_a = 0.0725;
lamda_dc = 0.6525; % 单位捕碳量能耗
P_D1=10; % 碳捕集固定能耗
P_BA = ones(1,24);
P_BA(1,:) = P_D1.* ones(1,24);  
K_q = 800;%弃风惩罚成本系数
K_T = 200; %碳交易价格
delta_h = 0.7; %碳配额系数
delta_xz = 0.9;%烟气分流比限值
C_FL = 165159.4 * 1e4;%碳捕集设备总成本
N_ZJ  = 15;%碳捕集设备折旧年限
r_rate = 0.08;%碳捕集电厂项目贴现率
P_G_max = 600; % 机组最大出力 单位：MW
P_G_min = 600 * 0.5; % 机组最小出力
R_u = 90; % 机组上爬坡
R_d = 90; % 机组下爬坡
T_on_min = 6; % 最小开机时间
T_off_min = 6; % 最小关停时间
M_MEA = 61.08; % M_MEA的摩尔质量
M_co2 = 44; % 二氧化碳的摩尔质量
theta = 0.4; % 再生塔解析量
CR = 0.4; % 醇胺溶液浓度(%)
rou_R = 1.01; % 醇胺溶液密度
V_CR = 10000; % 溶液储液装置容量
V_R0 = 5000;%富液存储器初始体积
V_L0 = 3000;%贫液存储器初始体积
rate_max = 400;
K_R = 1.17; % 乙醇胺溶剂成本系数
fai = 1.5; % 溶剂运行损耗系数
%% 决策变量
% 电力源出力
P_w = sdpvar(1,24,'full'); % 风电机组出力
P_w_cc = sdpvar(1,24,'full'); % 风电机组出力
P_w_net = sdpvar(1,24,'full'); % 风电机组出力
P_G = sdpvar(1,24,'full'); % 火电机组出力
% 碳捕集相关
P_N = sdpvar(1,24,'full'); % 机组净出力
P_CC = sdpvar(1,24,'full');% 碳捕集运行能耗
P_G_CC = sdpvar(1,24,'full');
P_OP = sdpvar(1,24,'full');% 碳捕集能耗
P_absorb = sdpvar(1,24,'full');
P_desorb = sdpvar(1,24,'full');
E_G = sdpvar(1,24,'full'); % 碳捕集机组产生的总碳排放
E_AB = sdpvar(1,24,'full'); % 机组捕获的总碳排放
E_DE = sdpvar(1,24,'full'); % 机组解析的总碳排放
E_liguid = 3000;%假设碳捕集装置富液中本来就含有3000t二氧化碳
E_NET = sdpvar(1,24,'full');
V_AB = sdpvar(1,24,'full'); % 
V_DE = sdpvar(1,24,'full');
V_R = sdpvar(1,24,'full'); % 富液体积
V_L = sdpvar(1,24,'full'); % 贫液体积
P_cut = sdpvar(1,24,'full'); % 系统可削减电负荷
P_DE = sdpvar(1,24,'full'); % 系统经过过需求响应后的电负荷
u = binvar(1,24,'full'); % 机组启停状态
T_on = sdpvar(1,24,'full'); 
T_off = sdpvar(1,24,'full');
delta = sdpvar(1,24);%烟气分流比

%% 约束条件
C = [];  %约束条件初始
C = [C,P_w == P_w_cc + P_w_net];

for t=1:24
    C = [C,0 <= P_G(t)];
    C = [C,P_G(t) == P_N(t) + P_G_CC(t)]; % 机组输出总功率
    C = [C,P_CC(t) == P_G_CC(t) + P_w_cc(t)]; % 碳捕集运行功率
    C = [C,P_CC(t) == P_BA(t) + P_OP(t)]; % 碳捕集运行功率
    C = [C,P_absorb(t) == lamda_a * E_AB(t)]; % 碳捕集运行功率
    C = [C,P_desorb(t) == lamda_dc * E_DE(t)]; % 碳捕集运行功率
    C = [C,P_OP(t) == lamda_a * E_AB(t)+  lamda_dc * E_DE(t)]; % 碳捕集设备运行能耗
    C = [C,E_G(t) == eg * P_G(t)];% 碳捕集机组产生的总碳排放
    C = [C,E_AB(t) ==  E_beta * delta(t) * E_G(t)]; % 机组捕获的二氧化碳总量
    C = [C,E_NET(t) ==  (1 - E_beta * delta(t)) * E_G(t)]; % 净碳排
    %C = [C, P_G_min - P_lamda * P_yita * E_beta * delta(t) * eg * P_G_max - P_BA <= P_N(t) <= P_G_max-P_BA]; % 【综合灵活运行方式】碳捕集电厂净出力范围    
    C = [C, 1 - delta_xz <= delta(t) <= delta_xz]; %烟气分流比限值约束
    C = [C, -0.02 * EleLoad(t) <= P_cut(t) <= 0];
    C = [C, P_DE(t) == EleLoad(t) + P_cut(t) ];% 切负荷后的电负荷
    C = [C, P_w_net(t) + P_N(t) == P_DE(t) ]; % 电力平衡
    C = [C,0 <= E_AB(t) <= P_yita * E_beta * eg * P_G_max];   % 510.3t二氧化碳
end
 
% 强化约束（新增）
C = [C, P_N >= 0.3 * P_G_max * u];  % 最低净出力保障电网稳定 
C = [C, P_G_CC >= P_BA .* u];   % 最低捕集能耗维持设备运行 
% 对照算例
% C = [C,P_w_cc==0];
%% 其他约束
% 火电机组出力约束
for t=1:24
    C = [C, P_G_min * u(t) <= P_G(t) <= P_G_max * u(t)];
    C = [C, P_G_min * u(t) <= P_G(t) <= P_G_max * u(t)];
    C = [C, 0 <= P_w(t) <= P_predict(t)];
    C = [C, 0 <= P_w_net(t) <= P_predict(t)];
    C = [C, 0 <= P_w_cc(t) <= P_predict(t)];
    C = [C, 0 <= P_G_CC(t)];
end

% 火电机组爬坡约束
for t = 2:24
    C = [C, P_G(t) - P_G(t-1) <= u(t) * R_u]; % 上爬坡约束
    C = [C, P_G(t-1) - P_G(t) <= u(t-1) * R_d]; % 下爬坡约束
end
% 火电机组启停约束
for t = 2:24
    % 更新连续开机与关停时间
    T_on(t) = T_on(t-1) + u(t-1);
    T_off(t) = T_off(t-1) + (1 - u(t-1));
    % 启停约束
    C = [C, (T_on(t-1) - T_on_min) * (u(t-1) - u(t)) >= 0];
    C = [C, (T_off(t-1) - T_off_min) * (u(t) - u(t-1)) >= 0];
end
% 碳捕集装置约束
for t=1:24
    C = [C,V_AB(t)==(M_MEA * E_AB(t))/(M_co2 * theta * CR * rou_R)]; % 电厂i的溶液存储器t时刻释放二氧化碳所需的溶液体积 注意单位换算
    C = [C,V_DE(t)==(M_MEA * E_DE(t))/(M_co2 * theta * CR * rou_R)];
    C = [C,0 <= V_AB(t)<=3000]; % 富液体积
    C = [C,0 <= V_DE(t)<=3000]; % 贫液体积
    for i= 1:t
       C = [C,V_R(i) == V_R0 + sum(V_AB(1:i) - V_DE(1:i))]; % 富液变化
       C = [C,V_L(i) == V_L0 + sum(V_DE(1:i) - V_AB(1:i))]; % 贫液变化
    end
    C = [C,0 <= V_R(t)<=V_CR]; % 富液体积
    C = [C,0 <= V_L(t)<=V_CR]; % 贫液体积
end 
    C=[C,V_L0 == V_L(24)];% 贫液初始平衡
    C=[C,V_R0 == V_R(24)];% 富液初始平衡
for t=1:23
     C = [C,0 <= abs(V_R(t+1) - V_R(t))<= rate_max * P_yita]; % 流速
     C = [C,0 <= abs(V_L(t+1) - V_L(t))<= rate_max * P_yita]; % 流速
end

%% 目标函数
F=0;
 for t=1:24
    C_loadcut(t) = 400 * abs(P_cut(t)); % 失负荷成本
    C_H(t) = cost * P_G(t); % 火电机组煤耗成本
    C_R(t) = K_R * fai * E_AB(t); % 溶剂损耗成本
    C_T(t) = K_T * (E_NET(t)- delta_h * P_G(t));% 碳交易成本 = 碳交易价格*（净碳排 - 配额碳排）
    C_q(t) = K_q *(P_predict(t) - P_w(t)); % 弃风惩罚成本
 end
 for t = 2:24
        C_k(t)= (u(t) * (1 - u(t-1)) + u(t-1) * (1 - u(t))) * C_start;
 end
F = F + sum(C_loadcut) + sum(sum(C_H)) +sum(sum(C_k)) + sum(sum(C_R)) + sum(C_T) + sum(C_q);

 %% 求解器配置
ops = sdpsettings('verbose',2,'solver','gurobi','gurobi.MIPGap',1e-6,'gurobi.Heuristics',0.9,'gurobi.TuneTimeLimit',0);
result = optimize(C,F,ops);
s_F = value(F);
s_F1 = value(sum(C_loadcut));
s_C_H = value(sum(C_H));
s_C_R = value(sum(C_R));
s_C_T = value(sum(C_T));
s_C_q = value(sum(C_q));
s_C_k = value(sum(sum(C_k)));
display(['最优规划结果 : ', num2str(s_F)]);
disp(['火电机组煤耗成本: ', num2str(s_C_H)]);
disp(['溶剂损耗成本: ', num2str(s_C_R)]);
disp(['碳交易成本: ', num2str(s_C_T)]);
disp(['弃风惩罚成本: ', num2str(s_C_q)]);
disp(['电能需求响应成本: ', num2str(s_F1)]);
disp(['机组启停成本: ', num2str(s_C_k)]);
%% 数据获取
s_P_w = value(P_w); % 风电机组出力
s_P_G = value(P_G); % 火电机组出力
s_P_N = value(P_N); % 机组净出力
s_u = value(u);
% 碳捕集相关
s_delta = value(delta);
s_P_CC = value(P_CC); % 碳捕集运行能耗
s_P_G_CC = value(P_G_CC); % 碳捕集运行能耗
s_P_w_cc = value(P_w_cc);
s_P_OP = value(P_OP); % 碳捕集能耗
s_P_absorb = value(P_absorb); % 碳捕集能耗
s_P_desorb = value(P_desorb); % 碳捕集能耗
s_E_G = value(E_G); % 碳捕集机组产生的总碳排放
s_E_AB = value(E_AB); % 机组捕获的总碳排放
s_E_DE = value(E_DE); % 机组解析的总碳排放
s_E_NET = value(E_NET); % 净碳捕集量
s_V_AB = value(V_AB); % 贫液流量
s_V_DE = value(V_DE); % 富液流量
s_V_R = value(V_R); % 富液体积
s_V_L = value(V_L); % 贫液体积
rate_absorb = s_V_AB/rate_max;
rate_desorb = s_V_DE/rate_max;
% 负荷
s_P_cut = value(P_cut); % 系统可削减电负荷
s_P_DE = value(P_DE); % 切负荷后的电负荷
% 碳排放量
emission_ini = sum(s_E_G);
emission_net = sum(s_E_NET);
e_av = emission_net/(sum(sum(s_P_G)));
disp(['初始碳排: ', num2str(emission_ini),'t']);
disp(['净碳排: ', num2str(emission_net),'t']);
disp(['平均碳排放强度: ', num2str(e_av)]);
% 碳捕集系统运行成本
sum_PG = sum(s_P_G);
sum_PN = sum(s_P_N);
 C_H_cc = zeros(1,24) ;
 C_H_net = zeros(1,24) ;
for t=1:24
    C_H_cc(t) = cost * s_P_CC(t); 
    C_H_net(t) = cost * s_P_N(t); 
end
C_net = sum(C_H_net);
C_cc= sum(C_H_cc);
disp(['净发电成本: ', num2str(C_net)]);
disp(['捕集二氧化碳成本: ', num2str(C_cc)]);
C_av_cc = C_cc / (sum(s_E_AB));

%% 数据分析与画图
% 电力系统
Plot_EleNet = zeros(4,24);
for t=1:24
    Plot_EleNet(1,t) = P_w_net(t);
    Plot_EleNet(2,t) = P_N(t);
    Plot_EleNet(3,t) = P_G_CC(t);
    Plot_EleNet(4,t) = P_w_cc(t);
end
Plot_EleNet = Plot_EleNet';
figure
bar(Plot_EleNet,'stacked');
hold on
plot(EleLoad,'-r^',...
                'Color',[1,0,0],...  
                'LineWidth',1,...
                'MarkerEdgeColor','k',...
                'MarkerFaceColor',[0 0 1],...
                'MarkerSize',5);
xlabel('时间/h');
ylabel('功率/kW');
title('电功率平衡');
hold on
legend('风电净出力','碳捕集机组净出力','碳捕集能耗g','碳捕集能耗w','电负荷',...
'FontSize',10,'Location','northwest','NumColumns',3);
% 风电出力
figure
plot(s_P_w,'r-s','LineWidth',1.5)
hold on
plot(P_predict,'c--','LineWidth',1.5)
legend({'风功率','风功率预测值'})
xlabel('时间/h');
ylabel('功率/kW');
title('风电功率');

%% 碳捕集机组
hours = 1:24; % 时段
% 电厂的功率构成
figure;
yyaxis left % 创建双y轴图，左侧y轴用于功率累加值
b = bar(hours, [s_P_N', s_P_G_CC',s_P_w_cc'], 'stacked','FaceColor','flat');
for k = 1:3
    b(k).CData = k;
end
ylabel('碳捕集电厂功率 (MW)');
yyaxis right % 创建双y轴图，右侧y轴用于烟气分流比
plot(hours, s_delta, 'k--', 'LineWidth', 1.5);
ylim([0 1]);
ylabel('烟气分流比');
title('电厂各部分功率组成');
xlabel('时段');
legend('净出力',  '火电机组给碳捕集装置', '风电机组给碳捕集装置','烟气分流比', 'Location', 'northeastoutside');
% 二氧化碳捕集量
figure
plot(s_E_G,'r-s','LineWidth',1.5)
hold on
plot(s_E_NET,'g-s','LineWidth',1.5)
hold on
plot(s_E_AB,'m--','LineWidth',1.5)
plot(s_E_DE,'c--','LineWidth',1.5)
legend('初始碳排','净碳排','吸收二氧化碳','解吸并压缩二氧化碳')
xlabel('时间/h');
ylabel('碳捕集量');
ylim([0 550]);
title('二氧化流向');


% 贫液、富液体积变化和流量图
figure;
subplot(2,1,1);
plot(hours, s_V_L, 'b-', 'LineWidth', 1.5);
hold on;
plot(hours, s_V_R, 'r-', 'LineWidth', 1.5);
hold on;
ylabel('体积 (m^3)');
xlabel('时间/h');
legend('贫液体积', '富液体积','Location', 'northeastoutside');
title('贫液和富液体积变化');

subplot(2,1,2);
plot(hours, s_V_AB, 'g-', 'LineWidth', 1.5);
hold on;
plot(hours, s_V_DE, 'm-', 'LineWidth', 1.5);
ylabel('流量 (m^3)');
xlabel('时间/h');
title('贫液和富液流速');
legend('贫液流量', '富液流量');