class ErrorHandler {
  static String getMessage(dynamic error) {
    if (error is Exception) {
      return _handleException(error);
    }
    return error?.toString() ?? '未知错误';
  }

  static String _handleException(Exception error) {
    switch (error.runtimeType.toString()) {
      case 'SocketException':
        return '网络连接失败，请检查网络设置';
      case 'TimeoutException':
        return '请求超时，请重试';
      case 'FormatException':
        return '数据格式错误';
      default:
        return '发生错误: ${error.toString()}';
    }
  }

  static bool shouldRetry(Exception error) {
    return error.runtimeType.toString() == 'SocketException' ||
           error.runtimeType.toString() == 'TimeoutException';
  }
}
