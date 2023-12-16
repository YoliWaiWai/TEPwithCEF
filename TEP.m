clear all
close all
clc


%% ***********Parameters **********
excelFilePath = '/Users/yuyue/Documents/GitHub/TEPwithCEF/工作簿1.xlsx';
N=6; % number of load nodes
L=15; % number of lines
Sbase=1e6;  % unit:VA
Total_Load = 1e3; %系统总有功负荷
loads_proportion = [0.10,0.30,0.05,0.20,0.30,0.05]; %1～6节点的负荷比例
P_loads = Total_Load * loads_proportion';
g_N_thermal = [780,260, 260]'; %火电机组容量
ramp_rate = 0.05; %爬坡率
g_r_thermal = g_N_thermal * ramp_rate; %﻿火电机组单位时间最大爬坡功率
M = 1e5;
% 节点支路关联矩阵

xlRange = 'B2:C16';
node_branch_matrix = zeros(N,L);
branches = xlsread(excelFilePath, '6节点系统支路参数', xlRange);

for i = 1:L
    start_node = branches(i, 1);
    end_node = branches(i, 2);
    % 在起始节点和终止节点的位置标记支路
    node_branch_matrix(start_node, i) = 1;
    node_branch_matrix(end_node, i) = -1;
end


% 线路电抗
line_reactance = xlsread(excelFilePath, '6节点系统支路参数', 'D2:D16');
initial_lines = xlsread(excelFilePath, '6节点系统支路参数', 'G2:G16');
B_vector = line_reactance ./ max(initial_lines, 1);% 计算每条线路的电抗
B_vector(initial_lines == 0) = inf;% 将没有规划线路的地方电抗设置为无穷大

%% ***********Variable statement**********
theta = sdpvar(N,1);
p = sdpvar(L,1);
x=binvar(L,1);
g = sdpvar(3,1);
%% ***********Constraints*************
Obj = 0;
Cons = [
x([1,3,4,6,7,9,11]) == 1,
node_branch_matrix * p == [g(1),0,g(2),0,0,g(3)]' - P_loads,
-(1-x)*M <= node_branch_matrix' * theta - p .* line_reactance <= (1-x)*M,
theta(1)==0,
0 <= g <= g_N_thermal
];
ops=sdpsettings('verbose',0,'solver','gurobi');
sol = optimize(Cons,Obj,ops);

%直流潮流约束

%机组发电功率约束
%% 绘图
s_x = value(x);
G = graph(branches(:,1),branches(:,2));
figure;
h = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);
connected_edges = find(s_x);
highlight(h, 'Edges', connected_edges, 'EdgeColor', [0, 1, 0], 'LineWidth', 2);
title('规划结果');

