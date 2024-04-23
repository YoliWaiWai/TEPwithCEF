%% 含碳捕集电厂的低碳电源规划模型
%模型和数据来自清华大学工学硕士学位论文《含碳捕集电厂的电力系统规划与运行决策方法研究》季震 第五章
clear all
close all
clc
%% *********** Parameters **********

%没有线路参数
U_cp=5; %燃气
U_hp=2; %核电
U_np=1; %抽蓄
U1 = U_cp+U_hp+U_np;%常规火电机组及其他类型发电机组
U_tp=4; %燃煤
U2 = U_tp;%新建常规

Y = 5;%总规划年份
i_rate = 0.08;%贴现率
n_age = 25;%机组运行年限
A = 0.25;%典型日d典型时段t的权重系数因子
r_W = 0.25;%风电规划容量比例系数
r_CP = 0.8;%碳捕集机组的规划容量比例系数
R_U = 0.05;%系统运行正备用需求
R_D = 0.02;%系统运行负备用需求
gamma_W = 0.4;%日负备用约束风电容量比例系数
loss = 1;%万元/MWh
C_INV = 0;%初始化投资成本
C_BN1 = xlsread('ccs4data',1,'C2:C5');%新建常规成本
C_BN2 = xlsread('ccs4data',1,'C6:C13');%新建其它类型成本
C_BR = 1.005*C_BN1;
C_BP = 1.182*C_BN1;
C_RN = 0.186*C_BN1;

%% *********** Variable statement **********
%投资决策变量
M_B = binvar(U1,Y);%常规火电机组及其他类型发电机组
M_BN = binvar(U2,Y);%新建常规
M_BR = binvar(U2,Y);%新建碳捕集预留CCR
M_BP = binvar(U2,Y);%新建碳捕集机组CCS
M_RN = binvar(U2,Y);%常规改造
M_RR = binvar(U2,Y);%CCR改造
Cons=[];
%同一台机组同一类投资(新建或者改造)在规划期间只能进行一次（5-14）
Cons = [Cons, sum(M_B,2)<=1];%对矩阵M的每一行求和，使其和小于等于1﻿
Cons = [Cons, sum(M_BN,2)<=1];
Cons = [Cons, sum(M_BR,2)<=1];
Cons = [Cons, sum(M_BP,2)<=1];
Cons = [Cons, sum(M_RN,2)<=1];
Cons = [Cons, sum(M_RR,2)<=1];
%投资状态变量(5-1)
I_B = sdpvar(U1, Y);%常规火电机组及其他类型发电机组
for i = 1:U1
    Cons=[Cons,I_B(i,y_1) == sum(M_B(i, 1:y_1))];
end

I_BN = sdpvar(U2,Y);
for i = 1:U2
    Cons=[Cons,I_BN(i,y_1) == sum(M_BN(i, 1:y_1))];
end

I_BR = sdpvar(U2, Y);
for i = 1:U2
    Cons=[Cons,I_BR(i,y_1) == sum(M_BR(i, 1:y_1))];
end

I_BP = sdpvar(U2, Y);
for i = 1:U2
    Cons=[Cons,I_BP(i,y_1) == sum(M_BP(i, 1:y_1))];
end

I_RN = sdpvar(U2, Y);
for i = 1:U2
    Cons=[Cons,I_RN(i,y_1) == sum(M_RN(i, 1:y_1))];
end

I_RR = sdpvar(U2, Y);
for i = 1:U2
    Cons=[Cons,I_RR(i,y_1) == sum(M_RR(i, 1:y_1))];
end
%% *********** Constraints *************
C_A1 = ((i_rate * (1 + i_rate)^n_age) / ((i_rate * (1 + i_rate)^n_age) - 1)) * C_BN * I_B;

%计算电源投资费用C_INV（5-3）
for y = 1:Y
        for u = 1:U 
            % 计算现值
            present_value = (1+i_rate)^(-y) * C_A(u, y);
            % 累加到总的投资成本
            C_INV = C_INV + present_value;
        end
end
%以电源投资费用与规划期内系统运行成本之和最小为目标函数(5-2)
Obj = C_INV + C_OPE;
for i=1:N
    Cons = [Cons, sum(M_B,1)<=1];
    Cons = [Cons, sum(M_B(i, 1:y_1))<=1];
end
Cons = [Cons, sum(M_B,2)<=1];

%% *********** Solve the problem ***********
ops=sdpsettings('verbose',2,'solver','gurobi');
sol = optimize(Cons,Obj,ops);
