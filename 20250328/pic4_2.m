%% 装机容量柱状图绘制代码 
% 数据输入（单位：GW）
data = [
    9   9    9    9    12   22;    % 火电机组（初始容量 + 5年规划）
    0   12   12   12   12   12;     % 碳捕集机组 
    0   0    0    0    0    0;      % 燃气机组 
    10  10   10   10   10   10      % 风电机组 
];
years = {'初始值','规划期1','规划期2','规划期3','规划期4','规划期5'}; % X轴标签 
labels = {'燃煤机组','碳捕集机组','燃气机组','风电机组'};    % 图例标签 
 
%% 绘图设置 
figure('Position',[100 100 800 500])  % 设置画布尺寸 
h = bar(data', 0.8, 'grouped');       % 绘制分组柱状图[5]()
colormap(lines(4))                    % 使用lines颜色映射[4]()
 
%% 可视化增强 
% 1. 坐标轴设置 
set(gca,'FontSize',12,'FontName','Arial')
xticklabels(years)
xlabel('规划期','FontSize',14)
ylabel('装机容量 / 100MW','FontSize',14)
title('规划期内各类型机组总装机容量','FontSize',16)
 
% 2. 数据标签（仅标注非零值）
for i = 1:numel(h)
    heights = h(i).YData;
    for j = 1:length(heights)
        if heights(j) > 0 
            text(h(i).XData(j)+h(i).XOffset, heights(j)+0.5,...
                num2str(heights(j)),'HorizontalAlignment','center',...
                'FontSize',10)
        end 
    end 
end 
 
% 3. 图例与网格 
legend(labels,'Location','northwest','FontSize',12)
grid on 