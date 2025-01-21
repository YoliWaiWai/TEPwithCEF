%%  日前调度
clc
clear
close all
%% 数据导入 
% 调度周期
T = 24;
% 风电预测功率
P_predict = [299.31684570,267.37369850,280.08537360,284.77268320,329.09958680,289.71075430,168.28435840,159.06405380,186.0346144,198.1329347,131.11925170,85.775255530,58.515213000,91.257579160,116.95062800,139.50968970,149.37751450,191.11097300,267.21249580,291.12690360,300.99492390,334.31913910,353.35715740,342.35149640];
% 电负荷
EleLoad = 0.3*[1209.1268,1391.49,1417.724,1431.1808,1398.852,1322.37,1410.948,1492.848,1554.336,1390.158,1770.804,1786.932,1512.252,1305.108,1210.398,1228.514,1440.852,1770.426,1969.128,1685.124,1488.746,1445.374,1286.138,1377.11];
% 净负荷
NetLoad = EleLoad - P_predict;
% 原始数据
figure
plot(P_predict,'c-<','LineWidth',1.5)
hold on
plot(EleLoad,'m-s','LineWidth',1.5)
plot(NetLoad,'r->','LineWidth',1.5)
legend('风电出力','电负荷','净负荷')
xlabel('时间/h');
ylabel('功率/kW');
title('原始数据');
%% 相关参数
a = 0.00336; % 成本系数a
b = 113.4; % 成本系数b
c = 7000; % 成本系数c
C_start = 31500; % 启停成本
eg = 0.9; % 火电机组i的碳排放强度 单位：t/（MW·h）
E_beta = 0.9; % 碳捕集效率
P_yita = 1.05; % 再生塔和压缩机最大工作状态系数
lamda_a = 0.0725;
lamda_dc = 0.6525; % 单位捕碳量能耗
P_D1=10; % 碳捕集固定能耗
P_BA = ones(1,24);
P_BA(1,:) = P_D1.* ones(1,24);  
K_q = 4000;%弃风惩罚成本系数
K_T = 120; %碳交易价格
delta_h = 0.7; %碳配额系数
delta_xz = 0.9;%烟气分流比限值
C_FL = 165159.4 * 1e4;%碳捕集设备总成本
N_ZJ  = 15;%碳捕集设备折旧年限
r_rate = 0.08;%碳捕集电厂项目贴现率
P_G_max = 600; % 机组最大出力 单位：MW
P_G_min = 300; % 机组最小出力
R_u = 50; % 机组上爬坡
R_d = 50; % 机组下爬坡
T_on_min = 6; % 最小开机时间
T_off_min = 6; % 最小关停时间
M_MEA = 61.08; % M_MEA的摩尔质量
M_co2 = 44; % 二氧化碳的摩尔质量
theta = 0.4; % 再生塔解析量
CR = 40; % 醇胺溶液浓度(%)
rou_R = 1.01; % 醇胺溶液密度
V_CR = 30000; % 溶液储液装置容量
V_R0 = 1000;%富液存储器初始体积
V_L0 = 5000;%贫液存储器初始体积
rate_max = 400;
K_R = 1.17; % 乙醇胺溶剂成本系数
fai = 1.5; % 溶剂运行损耗系数
%% 决策变量
% 电力源出力
P_w = sdpvar(1,24,'full'); % 风电机组出力
P_G = sdpvar(1,24,'full'); % 火电机组出力
% 碳捕集相关
P_N = sdpvar(1,24,'full'); % 机组净出力
P_CC = sdpvar(1,24,'full');% 碳捕集运行能耗
P_OP = sdpvar(1,24,'full');% 碳捕集能耗
P_absorb = sdpvar(1,24,'full');
P_desorb = sdpvar(1,24,'full');
E_G = sdpvar(1,24,'full'); % 碳捕集机组产生的总碳排放
E_AB = sdpvar(1,24,'full'); % 机组捕获的总碳排放
E_DE = sdpvar(1,24,'full'); % 机组解析的总碳排放
E_liguid = sdpvar(1,24,'full');
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
% 【综合灵活运行方式】碳捕集电厂数学模型 公式（1）-（3）
for t=1:24
    C = [C,0 <= P_G(t)];
    C = [C,P_G(t) == P_N(t) + P_CC(t)]; % 机组输出总功率
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
    C = [C, P_w(t) + P_N(t) == P_DE(t) ]; % 电力平衡
    C = [C,0 <= E_AB(t) <= P_yita * E_beta * eg * P_G_max];   % 510.3t二氧化碳
end

%% 其他约束
% 火电机组出力约束
for t=1:24
    C = [C, P_G_min * u(t) <= P_G(t) <= P_G_max * u(t)];
    C = [C, 0 <= P_w(t) <= P_predict(t)];
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
    C = [C,V_AB(t)==(M_MEA * E_AB(t))/(M_co2 * theta * CR/100 * rou_R)]; % 电厂i的溶液存储器t时刻释放二氧化碳所需的溶液体积 注意单位换算
    C = [C,V_DE(t)==(M_MEA * E_DE(t))/(M_co2 * theta * CR/100 * rou_R)];
    for i= 1:t
       C = [C,V_R(i) == V_R0 + sum(V_AB(1:i) - V_DE(1:i))]; % 富液变化
       C = [C,V_L(i) == V_L0 + sum(V_DE(1:i) - V_AB(1:i))]; % 贫液变化
       C = [C,E_liguid(i) ==  sum(E_AB(1:i) - E_DE(1:i))];
       C = [C,E_liguid(t) >=  0];
    end
    C = [C,0 <= V_R(t)<=V_CR]; % 富液体积
    C = [C,0 <= V_L(t)<=V_CR]; % 贫液体积
end 
%     C=[C,V_L0 == V_L(24)];% 贫液初始平衡
%     C=[C,V_R0 == V_R(24)];% 富液初始平衡
for t=1:23
     C = [C,0 <= abs(V_R(t+1) - V_R(t))<= rate_max * P_yita]; % 流速
     C = [C,0 <= abs(V_L(t+1) - V_L(t))<= rate_max * P_yita]; % 流速
end
%% 目标函数
F=0;
 for t=1:24
    C_loadcut(t) = 400 * abs(P_cut(t)); % 失负荷成本
    C_H(t) = a * P_G(t)* P_G(t) + b * P_G(t) + c; % 火电机组煤耗成本
    C_R(t) = K_R * fai * E_AB(t); % 溶剂损耗成本
    C_T(t) = K_T * (E_G(t) - E_AB(t)- delta_h * P_G(t));% 碳交易成本 = 碳交易价格*（净碳排 - 配额碳排）
    C_q(t) = K_q *(P_predict(t) - P_w(t)); % 弃风惩罚成本
 end
 for t = 2:24
        C_k(t)= (u(t) * (1 - u(t-1)) + u(t-1) * (1 - u(t))) * C_start;
 end
F = F + sum(C_loadcut) + sum(sum(C_H)) +sum(sum(C_k)) + sum(sum(C_R)) + sum(C_T) + sum(C_q);

 %% 求解器配置
ops = sdpsettings('verbose',2,'solver','gurobi','gurobi.MIPGap',1e-6,'gurobi.Heuristics',0.9);
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
s_P_OP = value(P_OP); % 碳捕集能耗
s_P_absorb = value(P_absorb); % 碳捕集能耗
s_P_desorb = value(P_desorb); % 碳捕集能耗
s_E_G = value(E_G); % 碳捕集机组产生的总碳排放
s_E_AB = value(E_AB); % 机组捕获的总碳排放
s_E_DE = value(E_DE); % 机组解析的总碳排放
s_E_NET = value(E_NET); % 净碳捕集量
s_E_liguid = value(E_liguid);
s_V_AB = value(V_AB); % 贫液流量
s_V_DE = value(V_DE); % 富液流量
s_V_R = value(V_R); % 富液体积
s_V_L = value(V_L); % 贫液体积
rate_absorb = s_V_AB/rate_max;
rate_desorb = s_V_DE/rate_max;
E_netpower_emisson = eg *s_P_N;
% 负荷
s_P_cut = value(P_cut); % 系统可削减电负荷
s_P_DE = value(P_DE); % 切负荷后的电负荷
%% 数据分析与画图
% 电力系统
for t=1:24
    Plot_EleNet(1,t) = P_w(t);
    Plot_EleNet(2,t) = P_N(t);
    Plot_EleNet(3,t) = P_CC(t);
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
plot(s_P_DE,'-g^',...
                'Color',[0,1,0],...  
                'LineWidth',1,...
                'MarkerEdgeColor','y',...
                'MarkerFaceColor',[1 0 1],...
                'MarkerSize',5);
xlabel('时间/h');
ylabel('功率/kW');
title('电功率平衡');
hold on
legend({['风电','碳捕集机组净出力','碳捕集能耗','电负荷','P-DE']},...
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
b = bar(hours, [s_P_N', P_BA', s_P_OP'], 'stacked','FaceColor','flat');
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
legend('净出力', '固定能耗', '运行能耗', '烟气分流比', 'Location', 'northeastoutside');
% 二氧化碳捕集量
figure
plot(s_E_G,'r-s','LineWidth',1.5)
hold on
plot(s_E_NET,'g-s','LineWidth',1.5)
hold on
plot(s_E_AB,'m--','LineWidth',1.5)
plot(s_E_DE,'c--','LineWidth',1.5)
plot(E_netpower_emisson,'r--','LineWidth',1.5)
legend('初始碳排','净碳排','吸收二氧化碳','解吸并压缩二氧化碳','净输出功率对应的CO2')
xlabel('时间/h');
ylabel('碳捕集量');
ylim([0 550]);
title('二氧化流向');


% 贫液、富液体积变化和流速图
figure;
subplot(2,1,1);
plot(hours, s_V_L, 'b-', 'LineWidth', 1.5);
hold on;
plot(hours, s_V_R, 'r-', 'LineWidth', 1.5);
hold on;
plot(hours, s_V_AB, 'g-', 'LineWidth', 1.5);
hold on;
plot(hours, s_V_DE, 'm-', 'LineWidth', 1.5);
ylabel('体积 (m^3)');
xlabel('时间/h');
legend('贫液存储器', '富液存储器', '吸收', '解吸','Location', 'northeastoutside');
title('贫液和富液体积变化');

subplot(2,1,2);
plot(hours, rate_absorb, 'g-', 'LineWidth', 1.5);
hold on;
plot(hours, rate_desorb, 'm-', 'LineWidth', 1.5);
ylabel('流速 (m^3/h)');
xlabel('时间/h');
title('贫液和富液流速');
legend('贫液流速', '富液流速');