# CTP（C++）开发常见坑全攻略  
> 下面把 **CTP 开发全过程**（环境搭建 → API 初始化 → 登录 → 报单/撤单 → 持仓同步 → 业务层 → 部署）划分为若干模块。每个模块列出 **常见问题、根本原因、对应的解决办法**，并配有 **最佳实践/示例代码**，帮助你在写代码前“一次性把坑踩平”。

---

## 目录
1️⃣ 环境与编译  
2️⃣ 动态库加载 / 运行时  
3️⃣ API 初始化 & 登录顺序  
4️⃣ 请求号（request_id）与订单引用（OrderRef）  
5️⃣ 心跳、断线重连 & 前置切换  
6️⃣ 合约订阅、额度与交易日切换  
7️⃣ 回调线程安全、数据拷贝  
8️⃣ 报单/撤单常见错误  
9️⃣ 持仓/资金同步与对账  
🔟 风控、限额与持仓校验  
1️⃣1️⃣ 多账户 / 多前置  
1️⃣2️⃣ 高频/性能优化  
1️⃣3️⃣ 日志、错误码统一处理  
1️⃣4️⃣ 容器化 / 生产部署注意事项  
1️⃣5️⃣ 终极检查清单（Checklist）

> **本文全部基于官方 CTP 6.x SDK（Windows / Linux）**，如果你使用的不是 6.x，请自行对照对应版本的 API 文档。

---

## 1️⃣ 环境与编译

| # | 症状 | 常见根因 | 规避/解决方案 |
|---|------|----------|----------------|
| 1 | `LNK2019: unresolved external symbol`（链接错误） | - 编译器使用 **MD/MT** 与官方 `.lib` 不匹配 <br>- 缺少系统库 `ws2_32.lib`、`winmm.lib` | - 在 **属性 → C/C++ → 代码生成** 中选择 ** `/MD`（多线程 DLL）**，与官方库保持一致 <br>- 在 **链接器 → 输入** 中手动添加 `ws2_32.lib; winmm.lib` |
| 2 | `error C2664: “int __stdcall CThostFtdcTraderApi::ReqOrderInsert(...)"` 参数不匹配 | - 包含的 `ThostFtdcUserApiStruct.h` 头文件版本与 DLL 不一致（如使用旧 SDK 的头文件） | - 保证 **头文件、库文件、DLL** 同属同一版本（统一放在 `ctp_sdk/` 目录，确保 `include` 与 `lib` 以及 `dll` 同步） |
| 3 | 编译报错 `C4996: ‘strcpy’: This function or variable may be unsafe.` | - 使用了 **不安全的 C‑style 字符串函数**（编译器默认开启安全检查） | - 通过 `#pragma warning(disable:4996)` 或者改用 `strncpy_s`、`std::strncpy`，推荐使用 **C++ string + `memcpy`** 方式填充结构体 |
| 4 | `fatal error LNK1120: 1 unresolved externals`（缺少 `ThostFtdc…`） | - 没有在项目中 **链接 `thostmduserapi.lib` / `thosttraderapi.lib`** | - 项目属性 → 链接器 → 常规 → **附加库目录** 加入 SDK 的 `lib` 目录，<br>链接器 → 输入 → **附加依赖项** 添加 `thostmduserapi.lib; thosttraderapi.lib` |

> **最佳实践**：在 CMake 项目中使用 `find_package(CTP REQUIRED)`，将 `INTERFACE_INCLUDE_DIRECTORIES`、`INTERFACE_LINK_LIBRARIES` 明确写出来，避免手动写路径。

```cmake
# CMake 示例（Windows）
add_library(ctp SHARED IMPORTED)
set_target_properties(ctp PROPERTIES
    IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/ctp_sdk/lib/thosttraderapi.dll"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_SOURCE_DIR}/ctp_sdk/include"
    INTERFACE_LINK_LIBRARIES ws2_32 winmm
)
target_link_libraries(my_app PRIVATE ctp)
```

---

## 2️⃣ 动态库加载 / 运行时

| # | 症状 | 常见根因 | 规避/解决方案 |
|---|------|----------|----------------|
| 1 | `ImportError: DLL load failed`（Python 调用）或 **C++ 程序启动即异常退出** | - 运行时找不到 **DLL**（64‑bit 与 32‑bit 不匹配）<br>- `PATH` 环境变量未包含 DLL 目录 | - 确认 **执行程序** 与 **DLL** 位宽一致（统一 64‑bit）<br>- 将 `ThostFtdcTraderApi.dll`、`ThostFtdcMdApi.dll` 加入系统 `PATH`，或在 `main()` 开头调用 `SetDllDirectory("path/to/dll")` |
| 2 | 运行时出现 **`ErrorID=68`（前置不可用）**，日志里却没有网络错误 | - DLL 版本与交易所前置不兼容（如使用 **CTP 6.0** 且前置已升级到 **6.5**） | - 下载并使用与前置对应的 **最新版 SDK**；在 `Release` 版和 `Debug` 版保持同步 |
| 3 | 进程在 **`Init()`** 时卡住/进入死循环 | - 前置地址写错（漏掉 `tcp://` 前缀）或端口不通 | - 统一采用 **`tcp://IP:Port`** 形式；在控制台使用 `telnet IP Port` 检查连通性 |
| 4 | 程序在 **Linux** 上提示 `undefined symbol: __imp_...` | - 链接 Windows DLL（`.so` 与 `.dll` 混用） | - 在 Linux 上必须使用官方提供的 **`.so`** 包（`libthostmduserapi.so`、`libthosttraderapi.so`）<br>确认 `LD_LIBRARY_PATH` 包含所在目录 |

> **调试技巧**：  
> - 使用 `Process Monitor (procmon)` 或 `strace` 监视 DLL 加载路径。  
> - 在 Windows 上打开 **事件查看器** → **应用程序**，搜索 “thosttraderapi.dll” 相关的错误信息。

---

## 3️⃣ API 初始化 & 登录顺序

> CTP 实例是 **单例**（每进程只能创建一次 `CreateFtdcTraderApi`），且 **所有回调必须在 `Init()` 之后才会触发**。顺序错误是最常见的导致登录不成功的原因。

| # | 正确顺序（示例） | 常见错误 | 解决办法 |
|---|------------------|----------|----------|
| 1 | `pTraderApi = CThostFtdcTraderApi::CreateFtdcTraderApi();` | **先** `Init()` 再 `RegisterFront` → 前置地址未生效 | 必须 **先** `RegisterFront` → `RegisterSpi` → **后** `Init()` |
| 2 | `pTraderApi->RegisterFront(front_addr);` | 省略这一步，导致默认 `127.0.0.1:21202` | 添加正确的前置地址 |
| 3 | `pTraderApi->RegisterSpi(&mySpi);` | `RegisterSpi` 放在 `Init` 之后，回调对象未注册 | 确保 `RegisterSpi` 在 `Init` 前完成 |
| 4 | `pTraderApi->Init();` | **未** 调用 `Init`，所有请求都不会发送 | 必须调用 `Init`，它会创建内部网络线程 |
| 5 | 登录请求在 `OnFrontConnected` 回调里发送 | 在 `main()` 中直接 `ReqUserLogin`，此时尚未建立 TCP 连接 | 把登录代码放到 `OnFrontConnected`，或在 `OnRspUserLogin` 前先判断 `IsConnected` 标记 |
| 6 | `pTraderApi->SetHeartBeatInterval(30);`（可选） | 忽略心跳设置，导致 **120 秒** 超时自动断线 | 推荐在 `RegisterFront` 后、`Init` 前加 `SetHeartBeatInterval`（单位秒） |

### 示例（C++）

```cpp
class CTPTrader : public CThostFtdcTraderSpi {
public:
    void Start(const std::string& front, const std::string& broker,
               const std::string& userid, const std::string& pwd) {
        brokerID_ = broker; userID_ = userid; password_ = pwd;

        // 1. 创建 API
        pTrader_ = CThostFtdcTraderApi::CreateFtdcTraderApi();

        // 2. 注册前置
        pTrader_->RegisterFront(front.c_str());

        // 3. 注册回调对象（本身）
        pTrader_->RegisterSpi(this);

        // 4. 心跳（30 秒一次）
        pTrader_->SetHeartBeatInterval(30);

        // 5. 初始化（启动内部网络线程）
        pTrader_->Init();

        // 6. 主线程阻塞（业务线程自行实现）
        while (!stop_) std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    // ------------------- 回调 -------------------
    void OnFrontConnected() override {
        // 前置已经连上，立即登录
        CThostFtdcReqUserLoginField login{};
        memset(&login, 0, sizeof(login));
        strcpy(login.BrokerID, brokerID_.c_str());
        strcpy(login.UserID,   userID_.c_str());
        strcpy(login.Password, password_.c_str());

        int reqId = ++g_req_id;
        if (!pTrader_->ReqUserLogin(&login, reqId)) {
            LOG_ERROR("[CTP] ReqUserLogin failed, reqId={}", reqId);
        }
    }

    void OnRspUserLogin(CThostFtdcRspUserLoginField* pRsp,
                        CThostFtdcRspInfoField* pInfo,
                        int reqId, bool isLast) override {
        if (pInfo && pInfo->ErrorID != 0) {
            LOG_ERROR("[CTP] Login failed: {} ({})", pInfo->ErrorMsg, pInfo->ErrorID);
            return;
        }
        LOG_INFO("[CTP] Login success, trading day={}", pRsp->TradingDay);
        // 登录成功后可订阅行情、查询持仓、发单等
        SubscribeAllInstruments();
        QueryAccountAndPosition();
    }
    // ------------------------------------------------
private:
    CThostFtdcTraderApi* pTrader_ = nullptr;
    std::string brokerID_, userID_, password_;
    std::atomic<int> g_req_id{0};
    bool stop_ = false;
    // 这里可以放置行情API、线程安全队列等
};
```

> **注意**：所有结构体（`CThostFtdc…Field`）**必须**先 `memset(...,0)`，否则未初始化的字符数组会产生随机字符，导致 **报文非法**（如 `ErrorID=100`）。

---

## 4️⃣ 请求号（request_id） 与 订单引用（OrderRef）

CTP 要求 **每一次异步请求**（登录、下单、撤单、查询等）都携带 **递增的 `int` 型 `request_id`**；同一笔订单的 `OrderRef` 必须是 **纯数字、长度 ≤ 13**（部分前置还有 ≤ 12），否则会返回 **`ErrorID=100`** 或 **`ErrorID=89`（重复请求）**。

| # | 常见错误 | 根因 | 解决方案 |
|---|----------|------|----------|
| 1 | `ErrorID=89`（请求号重复） | `request_id` 在 **重连**、**多线程** 中重新从 0 开始，产生冲突 | 使用 **全局原子递增** (`std::atomic<int> g_req_id{0};`) 并在 **每一次 API 调用** 前 `int cur = ++g_req_id;` |
| 2 | `ErrorID=100`（OrderRef 错误） | `OrderRef` 含有字母、中文或超过 13 位；或使用 `std::string::c_str()` 的临时指针导致悬空 | - `char orderRef[13] = {0};` <br> `snprintf(orderRef, sizeof(orderRef), "%012d", ++g_order_ref);` <br> `strcpy(pOrder->OrderRef, orderRef);` <br> **确保** `g_order_ref` 为 **`uint64_t`**，不溢出 |
| 3 | `OrderRef` 重复导致 **系统忙** (`ErrorID=1`) | 对同一笔订单多次调用 `ReqOrderInsert`（比如业务层在 `OnRspOrderInsert` 前就再次发单） | 在业务层维护 **“已下单集合”**（`std::unordered_set<std::string>`），成功回执后才加入集合，撤单成功后再移除 |
| 4 | `request_id` 超出 `int` 范围（极端高频） | 超过 2^31‑1，导致负数回传 | 使用 **`int64_t`** 转换为 `int` 时做 **取模**：`int reqId = static_cast<int>(++g_req_id % INT_MAX);`（CTP 只接受 32 位） |

### 示例：安全的下单封装

```cpp
class OrderManager {
public:
    // 统一的下单入口——返回 false 表示请求未发出
    bool SendMarketBuy(const std::string& instrument, int volume) {
        CThostFtdcInputOrderField order{};
        memset(&order, 0, sizeof(order));

        // 必填字段
        strcpy(order.BrokerID, brokerID_.c_str());
        strcpy(order.InvestorID, userID_.c_str());
        strcpy(order.InstrumentID, instrument.c_str());

        // 价格类型：市价
        order.OrderPriceType = THOST_FTDCEP_OPT_Market;
        order.Direction      = THOST_FTDCTD_D_Buy;
        order.CombOffsetFlag[0] = THOST_FTDCEF_O_Open;   // 开仓
        order.VolumeTotalOriginal = volume;

        // ---- OrderRef（13 位数字） ----
        char orderRef[13] = {0};
        snprintf(orderRef, sizeof(orderRef), "%012d", ++g_order_ref);
        strcpy(order.OrderRef, orderRef);   // 必须拷贝到结构体内部

        // ---- RequestId ----
        int reqId = ++g_req_id;

        bool ok = traderApi_->ReqOrderInsert(&order, reqId);
        if (!ok) LOG_ERROR("[Order] ReqOrderInsert failed, inst={}, vol={}", instrument, volume);
        return ok;
    }

    // 撤单（使用 OrderRef + OrderSysID）
    bool CancelOrder(const std::string& orderRef, const std::string& orderSysId) {
        CThostFtdcInputOrderActionField action{};
        memset(&action, 0, sizeof(action));
        strcpy(action.BrokerID, brokerID_.c_str());
        strcpy(action.InvestorID, userID_.c_str());
        strcpy(action.OrderRef, orderRef.c_str());
        strcpy(action.OrderSysID, orderSysId.c_str());
        action.ActionFlag = THOST_FTDCAF_Delete; // 撤单

        int reqId = ++g_req_id;
        return traderApi_->ReqOrderAction(&action, reqId);
    }

private:
    CThostFtdcTraderApi* traderApi_;
    std::string brokerID_, userID_;
    std::atomic<int> g_req_id{0};
    std::atomic<int> g_order_ref{0};
};
```

> **要点**：  
> - 所有 `char[]` 必须 **显式拷贝**（`strcpy` / `memcpy`），不能直接指向 `std::string.c_str()`（后者会在 `std::string` 重新分配后失效）。  
> - `OrderRef` **只用数字**，并且每次 **递增**，即使多账户也可以在前面加 **业务前缀**（如 `"01%011d"`），确保全局唯一。

---

## 5️⃣ 心跳、断线重连 & 前置切换

CTP 默认心跳间隔为 **120 秒**，如果网络卡顿或前置重启，客户端会在 **120 秒内没有心跳** 而触发 **`OnFrontDisconnected`**。如果没有实现 **自动重连**，系统会停顿。

| # | 常见现象 | 根因 | 防范方案 |
|---|----------|------|----------|
| 1 | 断线后 **不再收到** `OnRtnDepthMarketData`、`OnRtnOrder`，程序卡在 `while(!isConnected)` | 未实现 `OnFrontDisconnected` → `Reconnect` 逻辑 | 在 `OnFrontDisconnected` 中：<br>① `Release` 旧 API 对象（`pTrader_->Release()`）<br>② 重新 `CreateFtdcTraderApi`、`RegisterFront`、`RegisterSpi`、`Init`<br>③ **重新登录**、重新**订阅** |
| 2 | 连上后 **行情/持仓没有恢复** | 重连后没有再次执行 `Subscribe`、`QryAccount` | 将 **订阅/查询代码抽成独立函数**（如 `SubscribeAllInstruments()`、`QueryAccountAndPosition()`），在 `OnRspUserLogin` 与 **每次重连成功后** 都调用一次 |
| 3 | 心跳过短导致 **服务器主动断开** | `SetHeartBeatInterval` 设得 **太小**（如 < 5s） | 通常 **30~60 秒** 足够；若业务要求极低延迟，可在服务器端（经纪商）协商调整 |
| 4 | 前置切换（同一交易所多条线路）时 **登录成功后未切换** | 只在 `OnFrontConnected` 注册一次 `Front`，未在断线时切换至备用 IP | 在 `OnFrontDisconnected` 中记录 **当前 Front 列表**，依次尝试 `pTrader_->RegisterFront(backup_ip)`，再 `Init()`；**记得加 `Sleep(2000)`** 给网络留时间恢复 |
| 5 | `OnRspError`（统一错误回报）被忽略 | 在 `Spi` 中没有实现 `OnRspError`，导致错误信息丢失 | 必须实现 `OnRspError`，记录 `ErrorID`、`ErrorMsg`、`request_id`，并在业务层做 **告警/重试** |

### 示例：断线自动重连（简化版）

```cpp
class CTPTrader : public CThostFtdcTraderSpi {
public:
    // ...
    void OnFrontDisconnected(int nReason) override {
        LOG_WARN("[CTP] Front disconnected, reason={}", nReason);
        is_connected_ = false;
        // 立刻尝试重连（这里使用备用列表）
        Reconnect();
    }

    void OnHeartBeatWarning(int nTimeLapse) override {
        LOG_WARN("[CTP] Heartbeat warning, lapse {}s", nTimeLapse);
    }

    void OnRspUserLogout(CThostFtdcUserLogoutField* pLogout,
                         CThostFtdcRspInfoField* pInfo,
                         int requestId, bool isLast) override {
        LOG_INFO("[CTP] User logout, requestId={}", requestId);
        is_connected_ = false;
        Reconnect();
    }

private:
    void Reconnect() {
        // 1. 释放旧对象
        if (pTrader_) {
            pTrader_->Release();    // 必须调用，内部线程会安全退出
            pTrader_ = nullptr;
        }

        // 2. 根据备份列表循环尝试
        for (const auto& front : front_list_) {
            LOG_INFO("[CTP] Trying reconnect to {}", front);
            pTrader_ = CThostFtdcTraderApi::CreateFtdcTraderApi();
            pTrader_->RegisterFront(front.c_str());
            pTrader_->RegisterSpi(this);
            pTrader_->SetHeartBeatInterval(30);
            pTrader_->Init();

            // 等待 5~10 秒看是否会再次触发 OnFrontConnected
            std::this_thread::sleep_for(std::chrono::seconds(5));
            if (is_connected_) break; // 成功连接后 OnFrontConnected 会把 is_connected_ 置 true
        }

        if (!is_connected_) {
            LOG_ERROR("[CTP] All front reconnect attempts failed, will retry after 30s");
            std::this_thread::sleep_for(std::chrono::seconds(30));
            Reconnect(); // 再次递归尝试
        }
    }

    // 在 OnRspUserLogin 中把 is_connected_ 置 true，并重新订阅
    void OnRspUserLogin(/*...*/) override {
        is_connected_ = true;
        // 重新订阅、查询等
        SubscribeAllInstruments();
        QueryAccountAndPosition();
    }

    // 成员
    CThostFtdcTraderApi* pTrader_ = nullptr;
    std::vector<std::string> front_list_; // 多条前置 IP
    std::atomic<bool> is_connected_{false};
};
```

> **注意**：`Release()` 必须在 **所有** 回调退出后调用，否则内部网络线程可能仍在执行导致 **段错误**。可以在 `OnFrontDisconnected` 完成后，再 `sleep` 一段时间确保内部线程安全退出。

---

## 6️⃣ 合约订阅、额度与交易日切换

| # | 常见错误 | 根因 | 防范方案 |
|---|----------|------|----------|
| 1 | `ErrorID=50`（订阅合约超限） | 单前置最多 **2000** 条合约（某些前置 1000） | - **分批**（每批 ≤ 2000）<br>- 如需订阅 >2000，使用 **多账号/多前置** <br>- 将合约分区存入 **Map<Front, vector<string>>** ，分别调用 `pMdApi->SubscribeMarketData(..., cnt)` |
| 2 | 行情回调不完整（缺少 **历史** 数据）| `SubscribePublicTopic` / `SubscribePrivateTopic` 未设置正确的 **恢复模式** | 在 `Init` 前或登录成功后调用：<br>`pMdApi->SubscribePublicTopic(THOST_TERT_RESTART);`<br>`pMdApi->SubscribePrivateTopic(THOST_TERT_RESTART);` <br>（`THOST_TERT_RESUME` 为“从上次收到的点继续”，`THOST_TERT_QUICK` 为“只推送新快照”） |
| 3 | 合约代码写错导致 **`ErrorID=7`（合约不存在）** | 合约忘记添加交易所后缀（如 `IF2006` → `IF2006.CFFEX`）| 使用 `ReqQryInstrument` 先拉全市场列表，**统一保存** `InstrumentID + ExchangeID`，后续全部使用 `instrumentID + "." + exchangeID` 形式 |
| 4 | 跨天交易（如夜盘）收到 **`OnRtnTradingNotice`** 却未更新 `TradingDay` | 没有在 `OnRtnTradingNotice` 中更新全局 `trading_day_`，导致以后 `ReqOrderInsert` 把错误的 `TradingDay` 发送给前置 | 将 `OnRtnTradingNotice` 的 `TradingNoticeInfo` 中的 `TradingDay` 保存到全局变量，**每次下单前**使用该变量（有的前置不要求，但最好保持一致） |
| 5 | 订阅成功后 **行情延迟 10+ 秒** | 前置服务器在 **恢复模式**（`THOST_TERT_RESTART`）时先回放历史行情，业务层未过滤，导致堆积 | 在 `OnRtnDepthMarketData` 中检查 `UpdateTime` 与系统时间的差值，若超过阈值（如 1s）直接**丢弃**或只保留最新快照 |

### 示例：批量订阅（不超过 2000 条）

```cpp
void SubscribeInBatches(const std::vector<std::string>& contracts) {
    const size_t batchSize = 2000; // 前置上限
    size_t total = contracts.size();
    size_t pos = 0;

    while (pos < total) {
        size_t cur = std::min(batchSize, total - pos);
        std::vector<const char*> batch(cur);
        for (size_t i = 0; i < cur; ++i) {
            batch[i] = contracts[pos + i].c_str();
        }
        int ret = pMdApi->SubscribeMarketData(const_cast<char**>(batch.data()), static_cast<int>(cur));
        LOG_INFO("[MD] Subscribe {} contracts, ret={}", cur, ret);
        pos += cur;
        std::this_thread::sleep_for(std::chrono::milliseconds(200)); // 防止前置瞬间请求过载
    }
}
```

---

## 7️⃣ 回调线程安全、数据拷贝

CTP 所有回调（`OnRtn*`、`OnRsp*`）都在 **内部网络线程** 中执行。**千万别在回调里直接做**：

- 阻塞式 I/O（网络请求、文件写入、数据库写入）  
- 访问 **非线程安全** 的容器（如 `std::vector`、`std::map`）  
- 持久化对象的 **指针**（在回调结束后对象会被 SDK 复用）

### 典型坑

| # | 现象 | 根因 | 解决办法 |
|---|------|------|----------|
| 1 | 程序出现 **“Access violation”**（崩溃）| 回调里把 `CThostFtdcDepthMarketDataField* p` 直接存入全局指针，随后 SDK 复写内存 | **深拷贝**：`CThostFtdcDepthMarketDataField copy = *p;` 再把 `copy` 放入线程安全队列 |
| 2 | 行情处理延迟 5~10 秒 | 在 `OnRtnDepthMarketData` 中直接 `printf("%s\n", p->LastPrice)`，`printf` 被 **缓冲**，导致阻塞 | 用 **无锁队列**（如 `boost::lockfree::spsc_queue`）把 `copy` 推入；后台消费者线程负责打印/持久化 |
| 3 | 多个回调同时写同一日志文件出现 **交叉** | `std::ofstream` 在多个线程中没有加锁 | 使用 **spdlog::basic_logger_mt**（多线程安全）或自行 `std::mutex log_mtx` 包裹写日志 |
| 4 | `OnRtnTrade` 与 `OnRtnOrder` 触发顺序不一致导致状态错乱 | 业务层直接更新 `order_state`，没有对 **双方** 做统一处理 | 建议实现 **订单状态机**：所有 `OnRtnOrder`、`OnRtnTrade`、`OnRspOrderAction` 统一进入 `OrderManager::Update(const Event&)`，内部使用 **原子状态** 与 **锁** 维护一致性 |

### 安全回调模板（C++）

```cpp
class CTPTrader : public CThostFtdcTraderSpi {
public:
    // 把行情推入锁自由队列
    void OnRtnDepthMarketData(CThostFtdcDepthMarketDataField* pDepth) override {
        if (!pDepth) return;
        // 深拷贝
        CThostFtdcDepthMarketDataField tick = *pDepth; // 结构体整体复制
        // 放入无锁队列（单生产者/单消费者）
        tick_queue_.push(tick);
    }

    // 把订单回执推入同一队列（或分开）
    void OnRtnOrder(CThostFtdcOrderField* pOrder) override {
        if (!pOrder) return;
        CThostFtdcOrderField order = *pOrder;
        order_queue_.push(order);
    }

    // 主业务线程（消费者）示例
    void ProcessQueue() {
        while (running_) {
            // 处理行情
            CThostFtdcDepthMarketDataField tick;
            while (tick_queue_.pop(tick)) {
                // 这里可以做 K 线生成、策略计算等耗时操作
                handle_tick(tick);
            }
            // 处理订单
            CThostFtdcOrderField order;
            while (order_queue_.pop(order)) {
                order_manager_.Update(order);
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }

private:
    // 单生产者/单消费者无锁队列（Boost Lockfree 示例）
    boost::lockfree::spsc_queue<CThostFtdcDepthMarketDataField> tick_queue_{1024};
    boost::lockfree::spsc_queue<CThostFtdcOrderField> order_queue_{512};

    std::atomic<bool> running_{true};
    // 业务层对象...
};
```

> **注意**：上面的 `push`/`pop` 为 **非阻塞**，如果队列满则直接丢弃（或记录丢包统计），防止阻塞网络线程。

---

## 8️⃣ 报单 / 撤单 常见错误

| # | 错误码/现象 | 典型根因 | 处理/规避 |
|---|-------------|----------|-----------|
| 1 | `ErrorID=100`（OrderRef 错误） | `OrderRef` 里有非数字或太长 | 采用固定宽度 12/13 位数字，使用 `snprintf("%012d", ++g_order_ref)` |
| 2 | `ErrorID=1`（系统忙） | **请求速率过高**（下单频率 > 5 次/秒）| 在业务层加入 **限流**（令牌桶），或在 `OnRspOrderInsert` 收到回执后才继续发送 |
| 3 | `ErrorID=102`（撤单不存在） | 撤单前已经 **成交**，或撤单回执迟到导致二次撤单 | 只在 `OnRtnOrder` 状态为 `Submitted`/`PartiallyFilled` 时才允许撤单；撤单成功回执后立即 **删除本地撤单标记** |
| 4 | `ErrorID=17`（价格错误） | 对不支持市价单的合约使用 `Price=0` | 使用 `ReqQryInstrument` 查询合约的 `OrderPriceType`，若不包含 `THOST_FTDCEP_OPT_Market` 则改为限价单 |
| 5 | `ErrorID=105`（合约不存在） | 合约已退市或实际交易所代码不同，如 `RB2009`（已退市） | 通过 `ReqQryInstrument` 动态获取可交易列表，或在代码里维护 **合约失效表** |
| 6 | **报单成功但** **`OnRtnTrade` 丢失** | 前置开启 **`THOST_TERT_RESTART`**，导致 **回放历史交易** 时回报顺序不一致 | `OnRtnTrade` 缺失时可在 `OnRspQryTrade`（主动查询）补足；或者在 `OnRtnOrder` 与 `OnRtnTrade` 同步更新 |
| 7 | **因切换前置导致订单状态不更新** | 重连后未重新 **查询** `QryOrder`，导致本地订单保持 `Submitted` 状态 | 在 `OnFrontConnected` 或 `OnRspUserLogin` 完成后，**强制查询** 所有未决订单（`QryOrder`）并恢复本地状态 |
| 8 | **下单后 `IsActive` 为 false** | 将 `OrderPriceType`、`Direction`、`CombOffsetFlag` 填写错误（如 `OffsetFlag` 与 `Direction` 不匹配）| 完整检查组合：<br>```cpp
if (order.Direction == THOST_FTDCTD_D_Sell && order.CombOffsetFlag[0] == THOST_FTDCEF_O_Open)  // 合法
else if (order.Direction == THOST_FTDCTD_D_Sell && order.CombOffsetFlag[0] == THOST_FTDCEF_O_Close) // 合法
else LOG_ERROR("Invalid dir+offset combo");
``` |

### 常用的订单状态映射（简化）

| CTP `OrderStatus` | 含义 | 对应业务状态 |
|--------------------|------|--------------|
| `0` (AllTraded)   | 完全成交 | `FILLED` |
| `1` (PartTradedQueueing) | 部分成交、排队 | `PARTIAL` |
| `2` (PartTradedNotQueueing) | 部分成交、未排队 | `PARTIAL` |
| `3` (NoTradeQueueing) | 未成交、排队 | `PENDING` |
| `4` (NoTradeNotQueueing) | 未成交、未排队 | `REJECTED` |
| `5` (Canceled) | 已撤销 | `CANCELLED` |
| `6` (Unknown)   | 未知 | `UNKNOWN` |

> **实现建议**：在 `OrderManager::Update(const CThostFtdcOrderField&)` 中先 **找或创建** 本地订单对象，然后根据 `OrderStatus` 与 `ExecType`（`CThostFtdcTradeField`）更新 **持仓**、**盈亏**、**风控计数**。

---

## 9️⃣ 持仓 / 资金 同步与对账

CTP 只在 **成交回报** (`OnRtnTrade`) 和 **持仓查询** (`ReqQryInvestorPosition`) 中提供最新持仓信息。网络中断或前置切换时，**本地持仓** 很容易出现 “漂移”——实际仓位已平但本地仍残留。

| # | 症状 | 根因 | 解决方案 |
|---|------|------|----------|
| 1 | 持仓报表与实际不符（多出或少出合约） | **仅依赖** `OnRtnTrade` 累计，未在网络异常后重新 **查询** 持仓 | 在 **每次登录成功**、**每次前置切换后**、**每个交易日切换**都执行 `ReqQryInvestorPosition`，并 **完全覆盖** 本地持仓（先清空再填充） |
| 2 | 资金曲线出现 “跳空” | 同上，且 **未查询** `ReqQryTradingAccount` | 同步 `ReqQryTradingAccount`，跟踪 `Balance`、`Available`、`Margin`，每次查询结束后 **重新计算** 本地风险指标 |
| 3 | 多合约持仓时出现 **重复** `OnRtnPosition` | 前置使用 **`THOST_TERT_QUICK`**（只推最新），业务层错误认为是增量 | 使用 **`THOST_TERT_RESUME`** 或在 `OnRtnPosition` 中检查 `PositionDate`、`PosiDirection`，只在 **`IsLast`** 为 `true` 时完成一次全量刷新 |
| 4 | 持仓对账时出现 **“持仓冻结”** 与 `Margin` 不一致 | 未处理 **`OnRtnInstrumentStatus`** 里 `TradingStatus` 为 `Paused`，导致系统自动冻结头寸但业务未更新 | 在 `OnRtnInstrumentStatus` 中检测 `TradingStatus`，如果是 `THOST_FTDCIS_Frozen`，将对应合约 **冻结标记** 置位，避免误下单 |
| 5 | 持仓快照出现 **负数**（如 `Position` 为 -1） | `CThostFtdcInvestorPositionField` 中 `Position` 为 **有符号**（int），在 **多账户** 并发写时出现 **竞态**，导致同一合约被两次累加 | 把本地持仓结构体 **锁住**（`std::mutex`）或使用 **原子** `std::atomic<int>` 进行增减，确保 **单一线程** 完成更新后再读出 |

### 示例：登录后全量拉取持仓、资金

```cpp
void QueryAccountAndPosition() {
    // 1. 查询账户
    CThostFtdcReqQryTradingAccountField accReq{};
    memset(&accReq, 0, sizeof(accReq));
    strcpy(accReq.BrokerID, brokerID_.c_str());
    strcpy(accReq.InvestorID, userID_.c_str());
    trader_->ReqQryTradingAccount(&accReq, ++g_req_id);

    // 2. 查询持仓（全品种）
    CThostFtdcQryInvestorPositionField posReq{};
    memset(&posReq, 0, sizeof(posReq));
    strcpy(posReq.BrokerID, brokerID_.c_str());
    strcpy(posReq.InvestorID, userID_.c_str());
    // InstrumentID 留空 => 全部
    trader_->ReqQryInvestorPosition(&posReq, ++g_req_id);
}

// 在回报里统一处理
void OnRspQryInvestorPosition(CThostFtdcInvestorPositionField* pPos,
                               CThostFtdcRspInfoField* pInfo,
                               int reqId, bool isLast) override {
    if (pInfo && pInfo->ErrorID != 0) {
        LOG_ERROR("[CTP] QryPosition failed: {} ({})", pInfo->ErrorMsg, pInfo->ErrorID);
        return;
    }
    // 这里采用一次性覆盖策略（先清空再写）
    if (reqId != last_pos_req_id_) {
        position_map_.clear(); // 新一次查询开始
        last_pos_req_id_ = reqId;
    }
    addOrUpdatePosition(*pPos); // 自己实现的合约持仓 map

    if (isLast) {
        LOG_INFO("[CTP] Position query completed, total {} contracts",
                 position_map_.size());
    }
}
```

> **小技巧**：`ReqQryInvestorPosition` 每次最多返回 **500 条**（不同前置略有差异），所以必须在 `OnRspQryInvestorPosition` 中判断 `isLast`，并在 `isLast==true` 时**结束**本次查询，否则后面的查询会和上一次混在一起。

---

## 🔟 风控、限额与持仓校验

CTP 本身不提供统一的风控模型，**所有的仓位、下单、止盈止损限制** 必须在业务层自行实现。常见的坑往往是 **风控状态与实际持仓不一致**，导致爆仓或被交易所强平。

| # | 常见问题 | 根因 | 解决方案 |
|---|-----------|------|----------|
| 1 | **账户总持仓超限**（如持仓超 10 手）但风控仍允许下单 | 风控计数只在 **下单成功回执** 时加，**撤单**、**成交** 没同步减 | - 在 **`OnRtnTrade`** 与 **`OnRtnOrder`** 双向更新持仓计数 <br>- 在 **撤单成功** (`OnRspOrderAction`，`ErrorID=0`) 中 **减** 风控占用 |
| 2 | **单品种最大手数** 被突破 | 风控时仅检查 **本地持仓**，未考虑 **已报未成交的挂单** | - 维护 **“占用手数”** = `已成交手数 + 挂单手数` <br>- 挂单数在 `OnRtnOrder` 状态为 `Submitted`、`PartTradedQueueing` 时计入；成交后从挂单减去并加到已成交 |
| 3 | **止盈/止损失效** | 只依赖交易所条件单（`ContingentCondition`），但当前品种不支持 | - 在本地实现 **价格监控**：当 `tick.LastPrice >= stop_price` → 立即发送 **平仓市价单** <br>- 使用 **线程安全的价格阈值**，避免在 `OnRtnDepthMarketData` 里直接下单 |
| 4 | **风控日志/告警** 缺失 | 当 `ErrorID!=0` 时仅打印到 console，未上报监控平台 | - 统一 **ErrorLogger**，把 `ErrorID、ErrorMsg、requestId、timestamp` 写入 **Kafka/Redis** 或文件，便于告警系统（Prometheus + Alertmanager）监控 |
| 5 | **限仓**（如统一保证金比例）计算错误 | 使用 `double` 进行 **累计**，导致精度误差 | - 对 **手数、金额** 采用 **`int64_t`（单位：分）** 或 **`int`（手数）**，仅在展示时才转换为 `double` |
| 6 | **跨交易日** 风控参数未重置 | 风控表格只在 `OnFrontConnected` 初始化，未在交易日切换时刷新 | - 在 `OnRtnTradingNotice` 或 `OnRtnInstrumentStatus` 中检测交易日变化，重新加载 **每日风控配置**（如读取 `json`、`yaml`） |

### 简单的持仓+挂单占用计数示例（C++）

```cpp
class RiskControl {
public:
    // 检查是否可以下单（示例：总手数不超过 max_total_hand）
    bool canPlaceOrder(const std::string& instrument, int hand, Direction dir) {
        std::lock_guard<std::mutex> lock(mtx_);
        // 已持仓手数（正为多头、负为空头）
        int pos = position_[instrument];
        // 已挂单手数（正为买挂单、负为卖挂单）
        int pending = pending_orders_[instrument];

        // 把挂单算进去，避免同方向超过限制
        int effective = (dir == Direction::Long) ? pos + pending + hand
                                                : -pos - pending + hand;
        return std::abs(effective) <= max_total_hand_;
    }

    // 在下单成功回执时调用
    void onOrderInsert(const std::string& instrument, int hand, Direction dir) {
        std::lock_guard<std::mutex> lock(mtx_);
        pending_orders_[instrument] += (dir == Direction::Long ? hand : -hand);
    }

    // 在成交回执时调用（把挂单换成真实持仓）
    void onTrade(const std::string& instrument, int hand, Direction dir) {
        std::lock_guard<std::mutex> lock(mtx_);
        // 更新挂单
        pending_orders_[instrument] -= (dir == Direction::Long ? hand : -hand);
        // 更新持仓
        position_[instrument] += (dir == Direction::Long ? hand : -hand);
    }

    // 撤单成功回执
    void onCancel(const std::string& instrument, int hand, Direction dir) {
        std::lock_guard<std::mutex> lock(mtx_);
        pending_orders_[instrument] -= (dir == Direction::Long ? hand : -hand);
    }

private:
    std::mutex mtx_;
    std::unordered_map<std::string, int> position_;        // 手数
    std::unordered_map<std::string, int> pending_orders_; // 挂单手数
    const int max_total_hand_ = 20; // 示例上限
};
```

> **业务层调用示例**：在准备下单前 `if (!risk.canPlaceOrder(ins, vol, Dir::Long)) { LOG_WARN("风控拦截"); return; }`；下单成功回执 `OnRspOrderInsert` 再调用 `risk.onOrderInsert`，成交回执 `OnRtnTrade` 调用 `risk.onTrade`，撤单回执 `OnRspOrderAction` 调用 `risk.onCancel`。

---

## 1️⃣1️⃣ 多账户 / 多前置

| # | 常见问题 | 根因 | 解决方案 |
|---|----------|------|----------|
| 1 | **同一进程只能创建一个** `CThostFtdcTraderApi` 实例，导致多个账号冲突 | CTP SDK 在内部使用 **单例静态资源**（网络线程、日志） | - **每个账号** 建议在 **独立进程** 中运行（可用 `fork`/`systemd` 或容器化）<br>- 若必须同进程，需要 **分配不同的 `BrokerID/InvestorID`** 并在下单时**显式填入**（所有请求结构体都必须写完 `BrokerID`、`InvestorID`） |
| 2 | **前置切换后行情/订单不再推送** | 只在 `OnRspUserLogin` 里订阅，断线重连后忘记重新订阅 | - 将 **订阅函数**（`SubscribeAllInstruments`）提取为 **单独方法**，在 `OnRspUserLogin`、`OnFrontConnected`、`OnRspError`（当 `ErrorID=68`）均调用 |
| 3 | **跨账户持仓合并错误** | 把多个账户的持仓直接写入同一 `PositionMap`，键冲突 | - 为每个账户使用 **`AccountKey = brokerID + "." + investorID`** 作为二级 map 键：`position[accountKey][instrument]` |
| 4 | **请求号冲突**（不同账号共用同一 `request_id`） | `static int request_id` 全局共享 | - 每个 **API 实例**（即每个账户）持有 **独立的 `std::atomic<int>`**，不共享 |
| 5 | **多前置负载均衡** | 只在配置文件里写一个 `front`，单点故障导致全停 | - 在配置文件里写 **数组** `fronts = {"tcp://1.1.1.1:21205","tcp://2.2.2.2:21205"}`，在 `OnFrontDisconnected` 中轮切换到下一个未被标记为 **不可用** 的前置 |
| 6 | **不同前置返回的 `InstrumentID` 编码不统一**（有的返回 `IF2006`，有的返回 `IF2006.CFFEX`）| 前置版本不统一 | - 在 `OnRtnInstrumentStatus` 或 `OnRspQryInstrument` 中统一 **标准化**（去掉后缀或统一加后缀），业务层只使用统一格式 |

> **建议**：如果业务需要 **10 条以上** 前置或 **5 账号以上**，强烈推荐 **容器化**（Docker + Docker‑Compose / K8s）+ **微服务**，每个容器只跑 **1 套** `CTPTrader + CTPMarket`，再通过 **消息队列**（Kafka / RabbitMQ）进行指令与回报的统一分发。

---

## 1️⃣2️⃣ 高频 / 性能优化

| # | 性能瓶颈 | 解决思路 |
|---|----------|----------|
| 1 | **网络线程阻塞**（回调里做磁盘 I/O） | - 回调只做 **数据拷贝 + 入队**，耗时操作交给 **独立 CPU**（使用 `std::thread`、`boost::asio`） |
| 2 | **CPU 核争抢**（行情、订单、业务共享同一线程） | - 使用 **CPU 亲和性**（`SetThreadAffinityMask`）将 **行情线程**、**交易线程**、**策略线程**分别绑定不同核心 |
| 3 | **队列容量不足导致丢包** | - 使用 **环形缓冲区**或 **lock‑free queue**（Boost.Lockfree、folly::MPMCQueue），容量 > 10k |
| 4 | **频繁的 `memcpy`**（拷贝结构体） | - 对于 **原始行情**，直接使用 **指针引用** 并在消费者侧 `memcpy`，避免在回调里复制两次 |
| 5 | **心跳间隔过短**导致频繁 **`OnHeartBeatWarning`** 并增加网络负载 | - 采用 **30~60 秒** 心跳，除非交易所明确要求更短 |
| 6 | **统计信息（盈亏、手续费）** 计算在主线程导致阻塞 | - 把 **统计聚合** 放到 **独立的后台线程**，使用 **双缓冲** 或 **Atomic** 计数器 |
| 7 | **日志级别过低**（Debug）且同步写磁盘 | - 在生产环境只打开 **INFO / WARN / ERR**，使用异步日志库（spdlog async） |

### 示例：使用 Boost.Lockfree 实现无锁单生产者/单消费者

```cpp
#include <boost/lockfree/spsc_queue.hpp>

boost::lockfree::spsc_queue<CThostFtdcDepthMarketDataField> tick_queue{65536};

void CTPTrader::OnRtnDepthMarketData(CThostFtdcDepthMarketDataField* p) {
    if (p) {
        CThostFtdcDepthMarketDataField tick = *p; // 单次复制
        tick_queue.push(tick); // 非阻塞
    }
}

// 消费线程
void market_consumer() {
    CThostFtdcDepthMarketDataField tick;
    while (running) {
        while (tick_queue.pop(tick)) {
            // 耗时业务：K线、策略
            process_tick(tick);
        }
        std::this_thread::sleep_for(std::chrono::microseconds(10));
    }
}
```

> **注意**：如果 `push` 失败（队列满），可以记录 **丢包计数**，或使用 **环形覆盖**（根据业务容错要求决定）。

---

## 1️⃣3️⃣ 日志、错误码统一处理

| # | 问题 | 根因 | 方案 |
|---|------|------|------|
| 1 | **错误信息散落**在不同回调中，难排查 | `OnRspError`、`pRspInfo`、`ErrorMsg` 分散写入不同日志文件 | - 建立 **统一的 `ErrorLogger`**，所有回调统一调用 `log_error(reqId, ErrorID, ErrorMsg, "OnXxx")` |
| 2 | **错误码未本地化**，只能看到数字 | 没有错误码对照表 | - 在代码里维护 `std::unordered_map<int, std::string> CTP_ERR_MAP`（官方错误码文档复制），打印时拼接文字 |
| 3 | **日志格式不统一**导致搜索困难 | 各模块自行 `printf`、`cout` | - 使用 **spdlog**（异步）或 **log4cxx**，统一 JSON 结构：`{ "timestamp":"...", "module":"CTPTrader", "level":"ERROR", "reqId":123, "errorId":68, "msg":"前置不可用" }` |
| 4 | **错误未告警**，只在日志里**埋** | 没有告警阈值 | - 将 **ErrorID >= 50**（业务错误）通过 **Prometheus exporter** 上报 `ctp_error_total{id="68"}`，配合 Alertmanager 触发告警 |

### 示例：统一错误日志（spdlog async）

```cpp
#include <spdlog/spdlog.h>
#include <spdlog/async.h>

auto async_file = spdlog::basic_logger_mt<spdlog::async_factory>("ctperr",
                "logs/ctp_error.log", true);
async_file->set_pattern("%Y-%m-%d %H:%M:%S.%e [%l] %v");

void log_ctp_error(int reqId, int errId, const char* errMsg,
                   const char* callback) {
    async_file->error("[{}] reqId={}, errId={}, msg={}",
                      callback, reqId, errId, errMsg);
}

// 在回调里统一调用
void CTPTrader::OnRspError(CThostFtdcRspInfoField* pInfo, int reqId,
                           bool isLast) override {
    if (pInfo && pInfo->ErrorID != 0) {
        log_ctp_error(reqId, pInfo->ErrorID, pInfo->ErrorMsg, "OnRspError");
    }
}
```

---

## 1️⃣4️⃣ 容器化 / 生产部署注意事项

| # | 常见问题 | 根因 | 解决方案 |
|---|----------|------|----------|
| 1 | **容器内部无法连通前置** | 容器默认 `bridge` 网络，前置 IP 与宿主机不在同一子网 | - 使用 **host network** (`docker run --network host`) <br>- 或在 `docker-compose` 中 `network_mode: "host"` <br>- 若必须使用自定义网络，**在防火墙**上放通容器子网的前置 IP |
| 2 | **证书/License 文件找不到** | 未挂载 `License.dat` 或路径错误 | - `docker run -v /opt/ctp/license:/ctp/license` <br>- 在代码中使用绝对路径 `"/ctp/license/License.dat"` |
| 3 | **时区不一致导致交易日错误** | 容器默认 UTC | - 在 Dockerfile 中 `ENV TZ=Asia/Shanghai` 并 `RUN apk add --no-cache tzdata && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime`（Alpine） |
| 4 | **CPU 受限导致行情延迟** | `docker run --cpus=1` 只给 1 核 | - 根据业务需求分配 **≥2 核**，并使用 `--cpuset-cpus="0-2"` 固定核心 |
| 5 | **文件描述符不足**（`EMFILE`） | 默认 1024，CTP **行情+交易** 线程会打开 **2000+** 连接 | - 在容器入口脚本中 `ulimit -n 65535` <br>- 对宿主机也同样修改 `/etc/security/limits.conf` |
| 6 | **日志文件膨胀** | `spdlog` 同步写入，没有轮转 | - 使用 `spdlog::rotating_logger_mt`，设置 `max_size=10MB, max_files=5` |
| 7 | **进程收到 SIGTERM 后未释放** | CTP API 需要先 `Release`，否则内部网络线程仍在跑导致容器卡死 | - 捕获 `SIGTERM`/`SIGINT`，在回调结束后调用 `pTrader_->Release(); pMd_->Release();` 再 `exit(0)` |
| 8 | **K8s 中的 Pod 重启导致断线** | `livenessProbe` 检测不到心跳，误杀 | - 在 `livenessProbe` 中 **检查** CTP 业务是否已 **登录成功**（例如检查一个 `health` HTTP 接口返回 `connected=true`），而不是只检测进程存活 |

### Dockerfile 示例（基于 Ubuntu 22.04）

```dockerfile
FROM ubuntu:22.04

# 安装运行时依赖
RUN apt-get update && apt-get install -y \
    libboost-system-dev libboost-thread-dev \
    tzdata ca-certificates && rm -rf /var/lib/apt/lists/*

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 拷贝 CTP SDK（假设已经在宿主机 /opt/ctp/sdk）
COPY sdk/ /opt/ctp/sdk/
ENV LD_LIBRARY_PATH=/opt/ctp/sdk/lib:$LD_LIBRARY_PATH

# 拷贝业务二进制
COPY bin/ctp_trader /usr/local/bin/ctp_trader
COPY config/ /opt/ctp/config/

# 挂载证书、日志目录
VOLUME ["/opt/ctp/license", "/opt/ctp/logs"]

# 设置文件描述符上限
RUN echo "* - nofile 65535" >> /etc/security/limits.conf

# 入口脚本：处理信号、运行二进制
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

`entrypoint.sh`（捕获信号、优雅退出）：

```bash
#!/bin/bash
set -e

# 捕获 SIGTERM / SIGINT
function graceful_exit {
    echo "Caught termination signal, stopping CTP..."
    kill -SIGINT $CTP_PID
    wait $CTP_PID
    echo "CTP stopped."
    exit 0
}
trap graceful_exit SIGTERM SIGINT

# 启动主进程
/usr/local/bin/ctp_trader &
CTP_PID=$!
wait $CTP_PID
```

---

## 1️⃣5️⃣ 终极检查清单（Checklist）

| 项目 | 检查点 | 状态（✓/✗） |
|------|--------|--------------|
| **编译链** | 位宽一致（64‑bit）<br>链接 `ws2_32.lib`、`winmm.lib`<br>使用官方 `include`/`lib`/`dll` 同版 | |
| **DLL 加载** | `PATH` 包含 `ThostFtdc*.dll`<br>Linux `LD_LIBRARY_PATH` 配置正确 | |
| **初始化顺序** | `RegisterFront → RegisterSpi → SetHeartBeatInterval → Init` | |
| **登录** | 登录回调 `OnRspUserLogin` 正常返回 `ErrorID=0`<br>保存 `BrokerID`, `InvestorID` | |
| **请求/订单号** | `request_id` 使用 `std::atomic<int>` 递增<br>`OrderRef` 纯数字、≤13 位、全局唯一 | |
| **心跳** | `SetHeartBeatInterval` 30~60 秒<br>`OnHeartBeatWarning` 正常记录 | |
| **断线重连** | 实现 `OnFrontDisconnected` → `Release` → `CreateApi` → `RegisterFront` → `Init`<br>登录成功后**重新订阅** | |
| **订阅额度** | 单前置订阅 ≤2000 条<br>若超过使用多前置或多账号 | |
| **回调安全** | 所有 `On*` 回调仅做 **深拷贝 + 入队**<br>使用 **锁/无锁队列** 防止竞争 | |
| **订单/撤单** | `OrderRef` 正确、`request_id` 唯一<br>撤单前检查 `OrderStatus` 是否可撤<br>限速控制（≤5 次/秒） | |
| **持仓/资金对账** | 登录后 `ReqQryTradingAccount`、`ReqQryInvestorPosition` 完整返回 <br>`isLast` 判断结束 | |
| **风控** | 持仓、挂单、成交统一计数<br>止盈止损本地实现（若交易所不支持） | |
| **多账户/前置** | 每个账户独立 `request_id`/`OrderRef`<br>账号切换后重新登录、订阅 | |
| **日志/错误** | 统一 `spdlog` 异步日志<br>错误码 `ErrorID` + `ErrorMsg` 统一打印<br>错误 > 50 上报告警 | |
| **容器化** | `--network host` 或前置白名单<br>`License.dat` 挂载<br>`ulimit -n 65535`<br>`TZ=Asia/Shanghai`<br>捕获 SIGTERM 并调用 `Release` | |
| **性能** | 无阻塞回调、无锁队列、CPU 亲和性<br>日志级别适配生产（INFO）<br>心跳间隔 30s | |
| **测试** | **先跑官方 Demo**（登录、订阅、下单、撤单）<br>再跑 **最小化自研**（登录 → 订阅 → 单笔市价买 → 撤单）<br>仿真环境通过后再切正式 | |
| **监控** | 关键指标（`connected`, `order_sent`, `order_success`, `error_total`）通过 Prometheus Exporter 暴露 | |

> **使用方法**：在 CI / 自动化部署脚本里跑一次 `checklist.sh`（自行实现），如果有任何 **✗**，立即 **阻止发布**，并在日志里输出对应的检查项。

---

## 总结

1. **环境与位宽、链接库**是最基础的坑，先把编译通过再谈业务。  
2. **初始化顺序**必须严格：`RegisterFront → RegisterSpi → SetHeartBeatInterval → Init`。  
3. **请求号、订单引用**必须全局唯一且递增，使用 `std::atomic` 防止竞争。  
4. **回调只能做轻量入队**，所有耗时操作（日志、持久化、策略）都放到 **独立线程**。  
5. **断线重连**要 **Release → Re‑Create → 登录 → 重新订阅**，否则行情、订单会丢失。  
6. **持仓/资金**必须在 **每次登录**、**每次前置切换**、**每日交易切换**时全量查询并覆盖本地缓存。  
7. **风控**必须把 **挂单 + 已成交** 计入占用手数，撤单成功后及时减掉。  
8. **多账号/多前置**建议采用 **进程/容器隔离**，共享 `request_id`/`OrderRef` 极易冲突。  
9. **性能**关键就在 **回调不阻塞**、**无锁队列**、**CPU 亲和性**，高频策略可考虑 **Lock‑free** 与 **CPU Pinning**。  
10. **日志 & 错误码** 统一化、结构化、上报告警，防止“只看到数字、找不到根因”。  
11. **容器化** 必须处理网络、证书、时区、文件描述符、优雅退出，否则生产环境容易卡死。  

> **只要把上表中的每一行都检查一次，基本就可以避免 90% 以上的 CTP 开发坑**。如果在实际项目里还有 **特定错误码** 或 **奇怪行为**，把日志、错误码、调用栈贴出来，我可以帮你定位更细的根因。祝你开发顺利、交易稳健 🚀