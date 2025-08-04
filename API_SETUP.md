# 机场API配置说明

## 概述

为了在天气界面显示机场名称而不是仅显示ICAO代码，应用集成了API Ninjas的机场API服务。

## 获取API密钥

1. 访问 [API Ninjas](https://api.api-ninjas.com/) 官网
2. 点击 "Sign Up" 注册账户
3. 登录后，在控制台中找到您的API密钥
4. 复制API密钥

## 配置API密钥

1. 打开文件 `lib/services/airport_service.dart`
2. 找到第6行的 `_apiKey` 常量：
   ```dart
   static const String _apiKey = 'YOUR_API_KEY'; // 需要替换为实际的API密钥
   ```
3. 将 `YOUR_API_KEY` 替换为您从API Ninjas获取的实际API密钥

## API使用限制

- API Ninjas提供免费套餐，每月有一定的调用次数限制
- 应用已实现本地缓存机制，机场信息会缓存30天，减少API调用次数
- 如果API调用失败，界面会回退显示ICAO代码

## 功能说明

配置完成后，天气界面将显示：
- 机场全名（如：北京首都国际机场）
- ICAO和IATA代码（如：ICAO: ZBAA / IATA: PEK）
- 最近搜索历史也会显示机场名称

## 故障排除

如果机场名称无法显示：
1. 检查API密钥是否正确配置
2. 检查网络连接是否正常
3. 查看控制台是否有错误信息
4. 确认API密钥是否还有剩余调用次数

## 注意事项

- 请妥善保管您的API密钥，不要将其提交到公共代码仓库
- 建议在生产环境中使用环境变量来管理API密钥
- 机场信息缓存在本地，首次查询某个机场时需要网络连接