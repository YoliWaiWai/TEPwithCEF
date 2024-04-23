%% 碳捕集电厂在联合市场中的运行决策模型
%模型和数据来自清华大学工学硕士学位论文《含碳捕集电厂的电力系统规划与运行决策方法研究》季震
clear all
close all
clc
%% *********** Parameters **********

N = 1; % 碳捕集电厂数量
T = 24; % 时段数目

% 合约售电收入
P_CE = 415; %碳捕集电厂在待决策日t时段的计划出力
PI_CE = 400; %日前合约电价
Q_CEL = P_CE * T; %日前合约电量（2-16）
R_CEL = PI_CE * Q_CEL; %碳捕集电厂的合约售电收入（2-15）

%实时交易售电收入
PI_RE = [203,165,138,111,136,118,300,297,394,394,441,491,297,294,363,337,391,465,475,525,476,466,411,319];
x = 1:24;
% 绘制折线图
plot(x, PI_RE);
%% *********** Variable statement **********

P_G = sdpvar(T,1); %各时段等效发电出力
lambda_S = sdpvar(T,1); %各时段烟气分流比
r_S = sdpvar(T,1); %解析速率因子
R_SP = sdpvar(T,1); %旋转备用容量
R_GE = sdpvar(T,1); %旋转备用被调用时等效发电出力的提升量
R_CC = sdpvar(T,1); %旋转备用被调用时捕集系统运行能耗的降低量
I = binvar(T,1); %碳捕集电厂第t时段的启停状态，1-开机，0-停机

%% *********** Constraints *************
R_REL = sum(PI_RE.*(P_N - P_CE)); %碳捕集市场实时交易售电收入
Obj = R_CEL + R_REL + R_SPI + R_CAR - C_GEN - C_STA -C_OTH;
%% *********** Solve the problem ***********
ops=sdpsettings('verbose',2,'solver','gurobi');
sol = optimize(Cons,Obj,ops);

