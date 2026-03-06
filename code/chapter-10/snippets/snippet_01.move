module chapter_10::snippet_01;

const CURRENT_VERSION: u64 = 2;

public struct VersionedConfig has key {
    id: UID,
    version: u64,
    // ... 配置字段
}

// 升级时调用迁移函数
public entry fun migrate_v1_to_v2(
    config: &mut VersionedConfig,
    _cap: &UpgradeCap,
) {
    assert!(config.version == 1, EMigrationNotNeeded);
    // ... 执行数据迁移
    config.version = 2;
}
