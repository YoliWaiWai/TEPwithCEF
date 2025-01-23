% 已知参数
r = 0.08;     % 折现率
T_o = 25;     % 运行年限
annuity_factor = (r * (1 + r)^T_o) / ((1 + r)^T_o - 1);
c_gen_trans = 239940000; % 机组改造成本
A_gen_trans = c_gen_trans * annuity_factor;
Years = 25; % 假设总年数

% 计算改造的动态投资成本
Obj_inv = 0;
for year = 1:Years
    Obj_inv = Obj_inv + A_gen_trans / (1 + r)^(year - 1);
end

% 其他已知参数
P = 300; % 机组功率，单位：MW
coal_cost = 0.3171; % 燃煤机组运行成本，单位：元/kWh
ccs_cost = 0.4134; % 碳捕集机组运行成本，单位：元/kWh
cei = 0.905; % 燃煤机组碳排放强度，单位：t/100MWh
cei_ccs = 0.113; % 碳捕集机组碳排放强度，单位：t/MWh
carbon_tax = 145; % 碳税，单位：元/tCO2
carbon_quota = 78.61; % 碳排放基准值，单位：t/MWh

% 计算每年的收益
hours_per_year = 8760; % 一年的小时数
% 运行成本节约
cost_saving = (coal_cost - ccs_cost) * P * 1000 * hours_per_year;
% 碳减排收益
carbon_saving = (cei - cei_ccs) * P * hours_per_year * carbon_tax;
annual_income = cost_saving + carbon_saving;

% 计算盈利时间
profit_time = Obj_inv / annual_income;

fprintf('机组按照满负荷状态运行 %.2f 年后才能盈利。\n', profit_time);