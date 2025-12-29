import 'package:flutter/foundation.dart';

abstract class UseCase<T, Params> {
  Future<T> call(Params params);
}

@immutable
class NoParams {
  const NoParams();
}
