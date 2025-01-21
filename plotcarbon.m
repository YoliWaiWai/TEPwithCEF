% 定义Q和T的增幅百分比
Q = [20, 0, -20, -40, -60]; % Q系列
T = [0,20, 40, 60];           % T系列

% 定义数据矩阵
Z = [4.64E+05, 4.34E+05, 2.728E+05, 2.84E+05, 1.52E+05;   % Q4 (+20%)
     3.64E+05, 4.14E+05, 2.00E+05, 1.49E+05, 1.37E+05;    % T1 (+20%)
     1.44E+05, 3.62E+05, 1.38E+05, 1.29E+05, 1.26E+05;    % T2 (+40%)
     1.22E+05, 1.48E+05, 1.29E+05, 1.32E+05, 1.27E+05];   % T3 (+60%)

% 创建Q和T的网格
[Q_grid, T_grid] = meshgrid(Q, T);

% 确保Z的维度和Q_grid、T_grid匹配
Z = Z(1:size(T_grid, 1), 1:size(Q_grid, 2));

% 绘制三维立体图
figure;
surf(Q_grid, T_grid, Z);

% 添加标签和标题
% xlabel('Quota Variation (%)');
% ylabel('Tax Variation (%)');
zlabel('Carbon emissions(t)');
title('');

% 调整视角
view(135, 30);

% 启用网格
grid on;
