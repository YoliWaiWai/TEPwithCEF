% 创建绘图函数
function plotResults(year,Hours,s_Obj_ope,s_sum_type_g,s_sum_type_g_ccs,s_sum_type_g_gas,s_g_exist,s_pd_shed,P_load,s_I_lines,s_x_gen_coal_1,s_x_gen_coal_2,s_x_gen_coal_3,s_x_gen_coal_4,s_x_gen_ccs_1,s_x_gen_ccs_2,s_x_gen_ccs_3,s_x_gen_ccs_4,s_x_gen_gas_1,s_x_gen_gas_2,s_x_gen_gas_3,s_x_gen_gas_4,I,J,l_E)
    N = size(P_load, 1);
% 根据选择的年份绘制相应的图形
    subplot(2, 2, 1); % Change subplot to 2 rows and 2 columns
    % Plot yearly planning results
    sum_type_g_all = squeeze(sum(s_sum_type_g, 1));
    sum_type_g_all = sum(sum_type_g_all, 1);
    sum_type_g_all_ccs = squeeze(sum(s_sum_type_g_ccs, 1));
    sum_type_g_all_ccs = sum(sum_type_g_all_ccs, 1);
    sum_type_g_all_gas = squeeze(sum(s_sum_type_g_gas, 1));
    sum_type_g_all_gas = sum(sum_type_g_all_gas, 1);
    sum_g_exist = sum(s_g_exist, 1);
    sum_s_pd_shed = sum(s_pd_shed);
    sum_type_g_all = [sum_g_exist; sum_type_g_all;sum_type_g_all_ccs; sum_type_g_all_gas;sum_s_pd_shed];
    sum_type_g_all = sum_type_g_all(:,:,year)';
    h = bar(1:Hours, sum_type_g_all, 'stacked');
    hold on;
    pp = sum(P_load, 1);
    plot(1:Hours, pp(:,:,year), 'k', 'LineWidth', 1.5);
    hold off;
    xlabel('时段/h');
    ylabel('机组出力/MW');
    legend('原有机组','燃煤机组','碳捕集机组','燃气机组','失负荷','负荷');
    title(['第', num2str(year), '年机组出力情况']);
    max_load = max(P_load(:));
    ylim([0, max_load*12]); 

    subplot(2, 2, 3); % Add a new subplot for operating cost
    plot(1:Hours, sum(s_Obj_ope(:,:,year),1), 'b', 'LineWidth', 1.5);
    xlabel('时段/h');
    ylabel('运行成本/万元');
    title(['第', num2str(year), '年运行成本']);
    ylim([0, max(s_Obj_ope(:))+5]); % Set y-axis limit to start from 0
    % 绘制规划结果
    subplot(2, 2, [2, 4]); % Combine the last two subplots into one
    G = digraph(I,J);
    h2 = plot(G, 'Layout', 'force', 'EdgeColor', 'k', 'NodeColor', 'b', 'MarkerSize', 8);
    % 设置节点坐标
    %          1，  2，3，4，5，  6，  7， 8，  9，10，11，12，13，14，15，16， 17，18，  19， 20，21，22，23，24，  25，  26，27，28，29
    h2.XData = [0,  4, 2, 4, 10, 12, 12, 15, 10, 10, 7,  4,  1,  1, 4, 6,   8,  6,  8.5, 10, 11, 12, 7, 12, 10,  5.0, 7.5, 15, 1.0, 1.0];
    h2.YData = [0, -3, 0, 0, -3,  0, -3,  0,  0,  3, 0,  3,  3,  7.5, 10, 5,  5, 7.5, 7.5, 7.5, 5, 3, 10, 10,   12.5, 12.5, 15, 15, 15, 10];
    l_new = setdiff(find(round(s_I_lines(:,1)) == 1),l_E); %新建的线路
    highlight(h2,I(l_E),J(l_E),'LineWidth',3,'EdgeColor','k'); %已建设线路
    highlight(h2,I(find(round(s_I_lines(:,1))==0)),J(find(round(s_I_lines(:,1))==0)),'LineStyle','--','LineWidth',1,'EdgeColor','b'); %未建设线路
    highlight(h2,I(l_new),J(l_new),'LineStyle','--','LineWidth',3,'EdgeColor','g'); %新建设线路
    % 计算负荷需求的24小时平均值
    avg_load = mean(P_load(:,:,year), 2);
    % 在节点上标记负荷需求
    for i = 1:N
        if avg_load(i) > 0
            load_str = sprintf('负荷 %.2f', avg_load(i));
            text(h2.XData(i)+0.1, h2.YData(i)-0.1, load_str, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Color', '#FFA500', 'FontSize', 8);
        end
        if ismember(i, [5,9,11,13,21,22,25,27,28])
            num_gen1 = sum(s_x_gen_coal_1(i, :, year));   
            num_gen2 = sum(s_x_gen_coal_2(i, :, year)); 
            num_gen3 = sum(s_x_gen_coal_3(i, :, year));   
            num_gen4 = sum(s_x_gen_coal_4(i, :, year)); 
            label_str = sprintf('1型: %d\n2型: %d\n3型: %d\n4型: %d', num_gen1, num_gen2, num_gen3, num_gen4);
            text(h2.XData(i)+0.1, h2.YData(i)-0.1, label_str, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Color', 'r', 'FontSize', 8);
        end  
        if ismember(i, [5,9,11,13,21,22,25,27,28])
            num_gen1 = sum(s_x_gen_ccs_1(i, :, year));   
            num_gen2 = sum(s_x_gen_ccs_2(i, :, year)); 
            num_gen3 = sum(s_x_gen_ccs_3(i, :, year));   
            num_gen4 = sum(s_x_gen_ccs_4(i, :, year)); 
            label_str = sprintf('1型: %d\n2型: %d\n3型: %d\n4型: %d', num_gen1, num_gen2, num_gen3, num_gen4);
            text(h2.XData(i)+1.6, h2.YData(i)-0.1, label_str, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Color', 'g', 'FontSize', 8);
        end  
        if ismember(i, [5,9,11,13,21,22,25,27,28])
            num_gen1 = sum(s_x_gen_gas_1(i, :, year));   
            num_gen2 = sum(s_x_gen_gas_2(i, :, year)); 
            num_gen3 = sum(s_x_gen_gas_3(i, :, year));   
            num_gen4 = sum(s_x_gen_gas_4(i, :, year)); 
            label_str = sprintf('1型: %d\n2型: %d\n3型: %d\n4型: %d', num_gen1, num_gen2, num_gen3, num_gen4);
            text(h2.XData(i)+1.6, h2.YData(i)-0.1, label_str, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'Color', 'b', 'FontSize', 8);
        end  
    end    
    %legend(h2, '已建设线路', '未建设线路', '新建设线路','负荷', '新建机组');
end



