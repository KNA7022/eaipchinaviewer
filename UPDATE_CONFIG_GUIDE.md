# 更新配置指南

本应用支持区分Windows和Android平台的更新机制。以下是配置指南：

## 文件结构

在您的Gitee仓库中，需要创建以下JSON文件：

### 1. version_windows.json (Windows平台更新配置)
```json
{
  "version": "1.5.0",
  "notic": "Windows版本更新内容：\n1. 修复了PDF缓存清理问题\n2. 优化了界面显示\n3. 提升了性能",
  "url": "https://github.com/yourusername/yourrepo/releases/download/v1.5.0/eaipchinaviewer-windows-v1.5.0.zip",
  "Sponsors": "感谢以下用户的支持：用户A、用户B"
}
```

### 2. version_android.json (Android平台更新配置)
```json
{
  "version": "1.5.0",
  "notic": "Android版本更新内容：\n1. 修复了PDF缓存清理问题\n2. 优化了界面显示\n3. 提升了性能",
  "url": "https://github.com/yourusername/yourrepo/releases/download/v1.5.0/eaipchinaviewer-android-v1.5.0.apk",
  "Sponsors": "感谢以下用户的支持：用户A、用户B"
}
```

### 3. version.json (通用版本，用于其他平台)
```json
{
  "version": "1.5.0",
  "notic": "通用版本更新内容：\n1. 修复了PDF缓存清理问题\n2. 优化了界面显示\n3. 提升了性能",
  "url": "https://github.com/yourusername/yourrepo/releases",
  "Sponsors": "感谢以下用户的支持：用户A、用户B"
}
```

## 字段说明

- **version**: 版本号，格式为 "主版本.次版本.修订版本"
- **notic**: 更新说明，支持换行符 `\n`
- **url**: 下载链接
  - Windows: 通常指向exe安装包或zip压缩包
  - Android: 指向APK文件
  - 其他平台: 可指向发布页面
- **Sponsors**: 捐助者名单（可选）

## 更新行为

### Windows平台
- 检测到更新时，会直接打开下载链接
- 用户需要手动下载并安装
- 显示友好的提示对话框

### Android平台
- 检测到更新时，会自动下载APK文件
- 请求必要的安装权限
- 下载完成后尝试自动安装

### 其他平台
- 显示"当前平台暂不支持自动更新"的提示
- 用户需要手动访问下载页面

## 如何修改更新URL

当前的更新URL配置在 `lib/services/update_service.dart` 中：

```dart
static String get _updateUrl {
  if (Platform.isWindows) {
    return 'https://gitee.com/KNA7022/eaipchinaviewerupdate/raw/master/version_windows.json';
  } else if (Platform.isAndroid) {
    return 'https://gitee.com/KNA7022/eaipchinaviewerupdate/raw/master/version_android.json';
  } else {
    return 'https://gitee.com/KNA7022/eaipchinaviewerupdate/raw/master/version.json';
  }
}
```

要修改更新源，只需要：
1. 将URL中的仓库地址替换为您自己的仓库
2. 确保JSON文件路径正确
3. 重新编译应用

## 注意事项

1. **版本号格式**: 必须使用数字和点号的格式，如 "1.2.3"
2. **文件编码**: JSON文件必须使用UTF-8编码
3. **URL有效性**: 确保下载链接可以正常访问
4. **权限问题**: Android平台需要用户授予安装权限
5. **网络连接**: 更新检查需要网络连接

## 测试建议

1. 在发布新版本前，先测试JSON文件的格式和链接有效性
2. 在不同平台上测试更新流程
3. 确保版本号比较逻辑正确工作
4. 测试网络异常情况下的处理