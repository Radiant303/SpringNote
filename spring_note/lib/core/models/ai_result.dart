/// AI 操作结果的统一封装
///
/// 使用 Result 模式替代返回 null，明确区分成功和失败情况
sealed class AiResult<T> {
  const AiResult();

  /// 操作成功
  bool get isSuccess => this is AiSuccess<T>;

  /// 操作失败
  bool get isFailure => this is AiFailure<T>;

  /// 获取成功结果（如果失败则返回 null）
  T? get dataOrNull => switch (this) {
    AiSuccess(data: final data) => data,
    AiFailure() => null,
  };

  /// 获取错误信息（如果成功则返回 null）
  String? get errorOrNull => switch (this) {
    AiSuccess() => null,
    AiFailure(error: final error) => error,
  };

  /// 转换成功结果
  AiResult<R> map<R>(R Function(T data) transform) {
    return switch (this) {
      AiSuccess(data: final data) => AiSuccess(transform(data)),
      AiFailure(error: final error, code: final code) =>
        AiFailure(error: error, code: code),
    };
  }

  /// 处理结果
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(String error, String? code) onFailure,
  }) {
    return switch (this) {
      AiSuccess(data: final data) => onSuccess(data),
      AiFailure(error: final error, code: final code) => onFailure(error, code),
    };
  }
}

/// 成功结果
final class AiSuccess<T> extends AiResult<T> {
  const AiSuccess(this.data);

  final T data;

  @override
  String toString() => 'AiSuccess(data: $data)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiSuccess<T> &&
          runtimeType == other.runtimeType &&
          data == other.data;

  @override
  int get hashCode => data.hashCode;
}

/// 失败结果
final class AiFailure<T> extends AiResult<T> {
  const AiFailure({
    required this.error,
    this.code,
  });

  /// 错误信息
  final String error;

  /// 错误代码（可选）
  final String? code;

  @override
  String toString() => 'AiFailure(error: $error, code: $code)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiFailure<T> &&
          runtimeType == other.runtimeType &&
          error == other.error &&
          code == other.code;

  @override
  int get hashCode => Object.hash(error, code);
}
