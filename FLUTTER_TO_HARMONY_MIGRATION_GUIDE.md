# Flutter 到鸿蒙（HarmonyOS）项目迁移全流程指导

## 第一步：Flutter 项目分析框架

### 1. 项目架构模式
- 架构模式：本项目采用“分层+服务”架构，主要通过 Service 层（如 `update_service.dart`、`api_service.dart` 等）管理业务逻辑，UI 层为各个 `Screen`，数据模型独立（如 `models/` 文件夹）。
- 状态管理：主要使用 `ValueNotifier`、`ChangeNotifier` 进行简单的响应式管理，未见 Bloc、Provider、GetX 等复杂状态管理框架。
- 职责划分：UI、业务逻辑、数据模型分层较清晰，服务类负责网络、本地、更新等功能。

### 2. 核心功能模块划分
- 主要模块：
  - 登录与认证（`auth_service.dart`、`/login` 路由）
  - 主界面与导航（`home_screen.dart`）
  - 航图数据展示与切换（`models/`、`screens/`、`widgets/`）
  - PDF/PDFX 文件查看（`pdf_viewer_screen.dart`、`platform/pdf_viewer_platform.dart`）
  - 天气信息（`weather_screen.dart`）
  - 主题与设置（`theme_service.dart`、`/settings` 路由）
  - 版本更新与下载（`update_service.dart`）
  - 本地存储与缓存（`shared_preferences`、`config.ini`、`pdf_paths.txt`）
- 模块依赖关系：
  - UI 层依赖 Service 层获取数据和状态
  - Service 层依赖网络、本地存储、第三方库
  - 各模块通过路由和全局状态进行交互

### 3. 数据流管理（状态管理）
- 方案：主要使用 `ValueNotifier`、`ChangeNotifier`，部分页面用 `setState`。
- 状态提升：如下载进度、主题切换等用全局 `ValueNotifier`。
- 全局/局部状态：全局如主题、下载任务，局部如页面加载、搜索等。

### 4. 路由导航结构
- 路由表：采用 Flutter 标准路由（`Navigator.push`、`pushReplacementNamed`），路由集中在主入口和各 Screen。
- 页面跳转：通过命名路由和参数传递（如 `/login`、`/settings`）。
- 嵌套路由：无明显嵌套路由，页面结构较为扁平。

### 5. 网络请求处理
- 封装方式：主要使用 `http` 包，所有请求封装在 `api_service.dart`、`update_service.dart` 等 Service 层。
- 异步处理：使用 `async/await`，异常通过 try-catch 处理。
- 拦截器/错误处理：无专用拦截器，错误通过弹窗、SnackBar 反馈。

### 6. 本地数据存储方案
- 方案：
  - 偏好存储：`shared_preferences`（如 token、用户名等）
  - 文件存储：如 `config.ini`、`pdf_paths.txt`、下载的 PDF 文件
  - 无数据库（如 sqflite/hive）使用
- 加密/备份：未见加密与备份机制

### 7. UI组件库使用情况
- 主库：大量使用 Flutter 原生 Material 组件
- 第三方 UI：如 `fl_chart`、`syncfusion_flutter_charts`、`syncfusion_flutter_gauges` 用于图表和仪表盘
- 自定义组件：有部分自定义 Widget（如 `widgets/` 目录）

### 8. 第三方依赖库清单及用途

| 依赖包                      | 用途说明                         |
|-----------------------------|----------------------------------|
| flutter                     | 基础框架                         |
| http                        | 网络请求                         |
| shared_preferences          | 偏好存储                         |
| path_provider               | 路径获取（本地文件操作）          |
| webview_windows             | Windows 平台 WebView 支持         |
| crypto, pointycastle, asn1lib| 加解密相关                       |
| pdfx                        | PDF 文件查看                      |
| open_file                   | 打开本地文件                      |
| internet_file               | 网络文件下载                      |
| intl                        | 国际化、日期格式化                |
| url_launcher                | 启动外部浏览器/应用               |
| share_plus                  | 分享功能                         |
| permission_handler          | 权限申请                         |
| connectivity_plus           | 网络状态检测                     |
| flutter_markdown            | Markdown 渲染                    |
| package_info_plus           | 获取包信息                       |
| fl_chart                    | 图表绘制                         |
| syncfusion_flutter_charts   | 专业图表库                       |
| syncfusion_flutter_gauges   | 仪表盘/指针图表                   |

### 9. API 地址、用途与解析方式

| API 地址 | 用法用途 | 解析方式 |
|----------|----------|----------|
| https://www.eaipchina.cn/eaip/packageFile/BASELINE/{version}/EAIP{version}.{packageVersion}/EAIP{version}.{packageVersion}_Web.zip?token=xxx | 下载航图包 | 直接下载ZIP文件，保存到本地，解压或直接使用 |
| https://gitee.com/KNA7022/eaipchinaviewerupdate/raw/master/version.json | 检查App更新、获取公告 | 获取JSON，字段有version、notic、url、Sponsors等，需json.decode解析 |
| https://www.eaipchina.cn/eaip/api/package/list | 获取可用航图版本列表 | 返回JSON，data.data为版本数组，需json.decode解析 |
| https://www.eaipchina.cn/eaip/api/structure/{version} | 获取指定版本航图结构 | 返回JSON，data为结构树，需json.decode解析 |
| https://www.eaipchina.cn/eaip/api/login | 用户登录 | POST，返回token，需json.decode解析 |
| https://www.eaipchina.cn/eaip/api/weather/{icao} | 获取机场天气 | 返回JSON，需json.decode解析 |

- 主要API均为RESTful风格，返回内容多为JSON，解析方式统一用`json.decode`。
- 下载类API直接获取二进制内容，保存为文件。
- 认证、数据、结构、天气等API均需带token或参数，部分需POST。

如需对某一模块做更细致分析或需要代码级梳理，请告知具体需求！

---

## 第二步：鸿蒙项目规划

1. **推荐鸿蒙项目架构**
   - 推荐使用 MVVM 架构，结合 ArkUI（ArkTS）组件体系
   - 业务逻辑与 UI 分离，ViewModel 负责数据与状态
2. **模块映射方案**
   - 登录、主界面、数据展示、设置等模块，均可映射为鸿蒙 Feature Ability 或 Page Ability
   - Bloc/Provider 状态管理 → ArkTS 的 Observable/State/Store
   - 路由导航 → 鸿蒙的 Ability 跳转与页面路由
   - 网络请求 → ArkTS 的 http/Request/Fetch API
   - 本地存储 → ArkTS 的 LocalStorage、数据库、文件 API
   - UI 组件 → ArkUI 标准组件或自定义组件
3. **技术替代建议**
   - Bloc/Provider → ArkTS Store/Observable
   - Flutter 路由 → ArkUI PageRouter/AbilityRouter
   - http/Dio → ArkTS @ohos.net.http 或第三方库
   - shared_preferences → ArkTS LocalStorage
   - sqflite/hive → ArkTS RDB/RelationalStore
   - Material/Cupertino → ArkUI 标准组件
4. **第三方库替代方案**
   - 需根据功能查找 ArkTS 生态下的等价库或自行实现
   - 常用功能如二维码、图片选择、文件操作等 ArkTS 生态均有支持

---

## 第三步：关键功能模块代码实现指导

1. **页面布局 ArkTS 示例**
```ts
@Entry
@Component
struct MainPage {
  build() {
    Column() {
      Text('Hello HarmonyOS')
      Button('点击我')
        .onClick(() => this.onClick())
    }
    .width('100%')
    .height('100%')
  }
  onClick() {
    // 事件处理
  }
}
```
2. **网络请求封装**
```ts
import http from '@ohos.net.http';

let httpRequest = http.createHttp();
httpRequest.request(
  'https://api.example.com/data',
  {
    method: http.RequestMethod.GET,
    header: { 'Content-Type': 'application/json' },
  },
  (err, data) => {
    if (!err) {
      // 处理 data.result
    }
  }
);
```
3. **数据持久化方案**
```ts
import data_storage from '@ohos.data.storage';
let storage = data_storage.getStorageSync('mydb');
storage.putSync('key', 'value');
let value = storage.getSync('key', 'default');
```
4. **事件处理逻辑转换**
- ArkTS 事件绑定直接在组件属性上（如 onClick、onChange）
- Bloc/Provider 事件流 → ArkTS 方法调用或 Store 状态变更
5. **自定义组件开发**
```ts
@Component
struct MyCard {
  @Prop title: string;
  build() {
    Column() {
      Text(this.title)
      // ...
    }
  }
}
```

---

## 第四步：迁移最佳实践

1. **分阶段迁移策略**
   - 先梳理功能模块，优先迁移基础功能（如网络、存储、主界面）
   - 逐步迁移业务逻辑和 UI，最后迁移高级功能和自定义组件
2. **代码组织规范建议**
   - 按模块/功能分包，保持 View、ViewModel、Service、Model 分层
   - 公共工具类、常量、资源文件单独管理
3. **性能优化注意事项**
   - 合理使用 ArkUI 组件，避免过度嵌套
   - 网络、存储等异步操作注意线程和回调
   - 图片、列表等大数据量场景注意懒加载和分页
4. **常见坑点及解决方案**
   - Flutter 第三方库大多无法直接迁移，需查找 ArkTS 替代或自行实现
   - 路由、状态管理、生命周期等概念有差异，需适配鸿蒙范式
   - UI 适配需重构，不能直接复用 Flutter Widget
   - 注意权限、包名、签名等鸿蒙平台特有要求

---

如需针对具体模块的迁移代码示例或遇到具体技术难题，请随时补充说明！