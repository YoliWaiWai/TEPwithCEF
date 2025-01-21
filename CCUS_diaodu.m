clear all
close all
clc
% 定义参数
n = 10; % 机组数量
T = 24; % 日前调度时间段数量
T_intra = 96; % 日内调度时间段数量
T_real = 288; % 实时调度时间段数量

% 机组参数
a = [0.00048, 0.00031, 0.002, 0.00211, 0.00398, 0.00712, 0.00079, 0.00413, 0.00222, 0.00173];
b = [16.2, 17.3, 16.6, 16.5, 19.7, 22.3, 27.7, 25.9, 27.3, 27.8];
c = [1000, 970, 700, 680, 350, 370, 480, 660, 665, 670];
P_max = [455, 455, 130, 130, 162, 80, 85, 55, 55, 55];
P_min = [200, 150, 30, 25, 45, 20, 25, 10, 10, 10];
u_cost = [4500, 5000, 550, 560, 900, 170, 260, 30, 30, 30];
v_cost = [0.9, 0.92, 0.99, 0.98, 1.02, 1.05, 1.06, 1.12, 1.15, 1.1];

% 系统参数
sigma_T = 14.286; % 碳交易价格
sigma_Q = 50; % 弃风惩罚成本
sigma_S = 142.857; % 失负荷惩罚成本
R_up = 50; % 上爬坡速率
R_down = 50; % 下爬坡速率
% 决策变量
PG_day_ahead = sdpvar(n, T, 'full');
PS_day_ahead = sdpvar(T);
u_day_ahead = binvar(n, T);

PG_intra_day = sdpvar(n, T_intra, 'full');
PS_intra_day = sdpvar(T_intra);

PG_real_time = sdpvar(n, T_real, 'full');
PS_real_time = sdpvar(T_real);

% 目标函数
objective = sum(sum(u_cost .* u_day_ahead)) + sigma_T * sum(sum(a .* (PG_day_ahead.^2 + PG_intra_day.^2 + PG_real_time.^2) + b .* (PG_day_ahead + PG_intra_day + PG_real_time) + c)) + sigma_Q * sum(PS_day_ahead + PS_intra_day + PS_real_time);

% 约束条件
constraints = [];
for t = 1:T
    constraints = [constraints, sum(PG_day_ahead(:, t)) + P_W(t) - PS_day_ahead(t) == P_el(t)]; % 功率平衡
end

for t = 1:T_intra
    constraints = [constraints, sum(PG_intra_day(:, t)) + P_W_intra(t) - PS_intra_day(t) == P_el_intra(t)]; % 功率平衡
end

for t = 1:T_real
    constraints = [constraints, sum(PG_real_time(:, t)) + P_W_real(t) - PS_real_time(t) == P_el_real(t)]; % 功率平衡
end

for i = 1:n
    for t = 1:T
        constraints = [constraints, P_min(i) <= PG_day_ahead(i, t) <= P_max(i)]; % 出力上下限
    end
    for t = 1:T_intra
        constraints = [constraints, P_min(i) <= PG_intra_day(i, t) <= P_max(i)]; % 出力上下限
    end
    for t = 1:T_real
        constraints = [constraints, P_min(i) <= PG_real_time(i, t) <= P_max(i)]; % 出力上下限
    end
end

% 求解
options = sdpsettings('solver', 'gurobi');
sol = optimize(constraints, objective, options);
% 检查求解状态
if sol.problem == 0
    disp('Optimal solution found:');
    disp(value(PG_day_ahead));
    disp(value(PS_day_ahead));
    disp(value(PG_intra_day));
    disp(value(PS_intra_day));
    disp(value(PG_real_time));
    disp(value(PS_real_time));
else
    disp('Something went wrong!');
    disp(yalmiperror(sol.problem));
end