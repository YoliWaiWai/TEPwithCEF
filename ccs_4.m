%% 含碳捕集电厂的低碳电源规划模型
%模型和数据来自清华大学工学硕士学位论文《含碳捕集电厂的电力系统规划与运行决策方法研究》季震 第五章
clear all
close all
clc
%% *********** Parameters **********

%没有线路参数
u1 = 1;%常规火电机组及其他类型发电机组
U_cp=5; 
U_np=1;
U_hp=2;
u2 = 1;%新建常规
u3 = 1;%新建碳捕集预留CCR
u4 = 1;%新建碳捕集机组CCS
u5 = 1;%常规改造
u6 = 1;%CCR改造
Y = 5;%第y年
i_rate = 0.08;%贴现率
n_age = 25;%机组运行年限
A = 0.25;%典型日d典型时段t的权重系数因子
r_CP = 0.8;%碳捕集机组的规划容量比例系数
R_U = 0.05;%系统运行正、负备用需求
R_D = 0.02;%系统运行正、负备用需求
gamma_W = 0.4;%日负备用约束风电容量比例系数
loss = 1;%万元/MWh
C_INV = 0;%初始化投资成本

%% *********** Variable statement **********
%投资决策变量
M_B = binvar(U_cp+U_hp+U_np,Y);%常规火电机组及其他类型发电机组
Cons=[];
Cons = [Cons, sum(M_B,2)<=1];

M_BN = binvar(u2,Y);%新建常规
M_BR = binvar(u3,Y);%新建碳捕集预留CCR
M_BP = binvar(u4,Y);%新建碳捕集机组CCS
M_RN = binvar(u5,Y);%常规改造
M_RR = binvar(u6,Y);%CCR改造

%投资状态变量(5-1)
I_B = sdpvar(U_cp, Y);
for i = 1:U_cp
    Cons=[Cons,I_B(i,Y) == sum(M_B(i, 1:y_1))];
end

I_BN = zeros(u2,Y);
for i = 1:u2
    I_BN = sum(M_BN(i,1:y_1));
end

I_BR = zeros(u3, Y);
for i = 1:u3
    I_BR(i,Y) = sum(M_BR(i, 1:y_1));
end

I_BP = zeros(u4, Y);
for i = 1:u4
    I_BP = sum(M_BP(u, 1:y_1));
end

I_RN = zeros(u5, Y);
for i = 1:u5
    I_RN = sum(M_RN(u, 1:y_1));
end

I_RR = zeros(u6, Y);
for i = 1:u6
    I_RR = sum(M_RR(u, 1:y_1));
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
