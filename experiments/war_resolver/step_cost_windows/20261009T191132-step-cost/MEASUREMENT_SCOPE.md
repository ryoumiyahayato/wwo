本轮测量为既有连续合成 main 场景，seeds71、109，0→1800游戏秒、quota7；空间阻断、观察报告、人物知识、六次决策、延迟命令、权限复验、有限补给和临时配属均由原场景产生。它不代表历史战争、完整战术校准或正式玩法。

外层推进以调用者调用前至实际返回后的计时为准，每次调用独立求和。输入/admission、调用者替换返回字典、结束释放、查询、JSON序列化和上传分别计量。advance_loop_inclusive含调用者循环处理，不能与api_sum混用。primitive计时包围原_step，决策child spans位于该primitive内部，不能再次相加当总耗时。primitive后的physical sink callback、resume结果整理和API最终清理另列。只比较同sample_id/call_id/primitive_id关联的span，不用不同最大值相减。

诊断默认OFF。全局top32、指定阶段各8、辅助调用环上限2048、阶段桶64；二级child top另有32上限和五个固定桶，已预登记。辅助调用记录只保留产生高成本样本的调用，未保留和淘汰计数分别记录。数据只保存稳定ID、整数和数值摘要；没有world、unit、job、result强引用。新诊断状态OFF时为两个null槽、一个Segment整数及固定阶段名集合。

宽采样v1全量开销约翻倍，v2/v3/v4逐步减少。最终宽采样对due/apply_units/apply_start/release_jobs/clear_delta/scope_capacity全量计时，其余阶段取第一及每第16次；频次来自原完整phase计数。累计观测值为真实采样和，估计总量为采样均值×原频次，存在系统采样偏差；candidate样本的实际处理比例与全体比例不同。其30–40%总扰动使时间排行仅作探索参考，不能当OFF性能。部分上下文记录unit_id为源单位；目标candidate ID未完整保留，非决策report标签也有描述性hint，不据此宣称全对象归因。

二级只观察已定位的company六次决策及99次due父原语，停用其他宽采样。五组交错配对的api_sum中位变化为seed71 -0.72%、seed109 +8.86%；负值不证明负开销，样本有明显墙钟波动。五次不是稳定p95保证。完整样本、最大值、直方图和各轮扰动均保留。直方图为整数微秒的2次幂上界桶，近似中位区间不作精确分位数。

copy_top_level_item_count只统计复制记录的顶层键，route_history_items另计；不等于递归总项数或native复制字节。离线JSON尺寸来自最终公开unit的紧凑UTF8编码，约1.0–1.3KiB，只用于规模档位，不能替代当时所有copy或内存分配量。早期cleanup估计重复累计携带字典规模，相关旧字段弃用但原样保留；更正版本只数实际已知释放触发分支，复核得到279个plan项、550个阶段间incoming项、末次8项，apply_start为0。

end_world_cleanup字段实际测量调用者释放scenario句柄；弱引用复核和显式诊断/公开结果释放另见raw-evidence.zip内CLEANUP_REFERENCE_RESULT.json，不将其泛化为native分配器回收。API边界pending峰值6、末尾事件/报告0、最终提交滞后0，不代表每个内部瞬间的全量峰值。冻结运行和测试指纹：da06177e42019e31545a20cd05273ec4eaee80ef3ee2725ab616bd5748b51c60。Windows旧测试失败为0，原资源退出matcher保留，原始normal/quota混合trace差异未重排或删记录。
