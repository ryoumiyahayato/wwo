# WOLITZKY2022

[Production Networks, Lecture4, 6.207/14.15 Networks](https://ocw.mit.edu/courses/14-15-networks-spring-2022/mit14_15s22_lec4.pdf)

实际阅读：Slides9,13–16/PDF8,12–15; title and credit text。版本：MIT OpenCourseWare Spring2022。

原问题为Leontief生产网络。分析者见W、最终需求y和技术α；固定比例式xi=(1/α)min_j(xij/wij)，总平衡y=(I−αWᵀ)x。状态为技术系数矩阵，输出计划产出；系数方向是生产者i使用投入j。课堂归一化的份额/总stuff不是异质商品质量守恒。参数W、α，逆解另需可逆性；没有订单时延或资金限制。证据为教学代数；原文复杂度UNKNOWN，独立遍历k个正配方投入O(k)，不代表全网络求解。

最小未来纯函数（独立）：q=min_j(现有可用量j/配方系数j)，再受产能/日期约束；系数单位必须是投入j单位/产出i单位。反例1煤+1钢→1工具不能以数量2→1判质量丢失；钢绑定时多煤不增产。TEST_AS_REFERENCE固定配方可行性；全局即时逆解DEFER，不读取未来库存。
