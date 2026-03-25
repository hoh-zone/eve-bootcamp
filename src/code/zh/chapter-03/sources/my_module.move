// 文件：sources/my_contract.move

// 模块声明：包名::模块名
module my_package::my_module {

    // 导入依赖
    use sui::object::{Self, UID};
    use sui::tx_context::TxContext;
    use sui::transfer;

    // 结构体定义（资产/数据）
    public struct MyObject has key, store {
        id: UID,
        value: u64,
    }

    // 初始化函数（合约部署时自动执行一次）
    fun init(ctx: &mut TxContext) {
        let obj = MyObject {
            id: object::new(ctx),
            value: 0,
        };
        transfer::share_object(obj);
    }

    // 公开函数（可被外部调用）
    public fun set_value(obj: &mut MyObject, new_value: u64) {
        obj.value = new_value;
    }
}
