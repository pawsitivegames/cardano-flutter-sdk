// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CardanoError {
  String get field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoErrorCopyWith<CardanoError> get copyWith =>
      _$CardanoErrorCopyWithImpl<CardanoError>(
          this as CardanoError, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoErrorCopyWith<$Res> {
  factory $CardanoErrorCopyWith(
          CardanoError value, $Res Function(CardanoError) _then) =
      _$CardanoErrorCopyWithImpl;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoErrorCopyWithImpl<$Res> implements $CardanoErrorCopyWith<$Res> {
  _$CardanoErrorCopyWithImpl(this._self, this._then);

  final CardanoError _self;
  final $Res Function(CardanoError) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? field0 = null,
  }) {
    return _then(_self.copyWith(
      field0: null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// Adds pattern-matching-related methods to [CardanoError].
extension CardanoErrorPatterns on CardanoError {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(CardanoError_InvalidAddress value)? invalidAddress,
    TResult Function(CardanoError_InvalidMnemonic value)? invalidMnemonic,
    TResult Function(CardanoError_DerivationError value)? derivationError,
    TResult Function(CardanoError_SerializationError value)? serializationError,
    TResult Function(CardanoError_NetworkError value)? networkError,
    TResult Function(CardanoError_InvalidKey value)? invalidKey,
    TResult Function(CardanoError_CslError value)? cslError,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case CardanoError_InvalidAddress() when invalidAddress != null:
        return invalidAddress(_that);
      case CardanoError_InvalidMnemonic() when invalidMnemonic != null:
        return invalidMnemonic(_that);
      case CardanoError_DerivationError() when derivationError != null:
        return derivationError(_that);
      case CardanoError_SerializationError() when serializationError != null:
        return serializationError(_that);
      case CardanoError_NetworkError() when networkError != null:
        return networkError(_that);
      case CardanoError_InvalidKey() when invalidKey != null:
        return invalidKey(_that);
      case CardanoError_CslError() when cslError != null:
        return cslError(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(CardanoError_InvalidAddress value) invalidAddress,
    required TResult Function(CardanoError_InvalidMnemonic value)
        invalidMnemonic,
    required TResult Function(CardanoError_DerivationError value)
        derivationError,
    required TResult Function(CardanoError_SerializationError value)
        serializationError,
    required TResult Function(CardanoError_NetworkError value) networkError,
    required TResult Function(CardanoError_InvalidKey value) invalidKey,
    required TResult Function(CardanoError_CslError value) cslError,
  }) {
    final _that = this;
    switch (_that) {
      case CardanoError_InvalidAddress():
        return invalidAddress(_that);
      case CardanoError_InvalidMnemonic():
        return invalidMnemonic(_that);
      case CardanoError_DerivationError():
        return derivationError(_that);
      case CardanoError_SerializationError():
        return serializationError(_that);
      case CardanoError_NetworkError():
        return networkError(_that);
      case CardanoError_InvalidKey():
        return invalidKey(_that);
      case CardanoError_CslError():
        return cslError(_that);
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(CardanoError_InvalidAddress value)? invalidAddress,
    TResult? Function(CardanoError_InvalidMnemonic value)? invalidMnemonic,
    TResult? Function(CardanoError_DerivationError value)? derivationError,
    TResult? Function(CardanoError_SerializationError value)?
        serializationError,
    TResult? Function(CardanoError_NetworkError value)? networkError,
    TResult? Function(CardanoError_InvalidKey value)? invalidKey,
    TResult? Function(CardanoError_CslError value)? cslError,
  }) {
    final _that = this;
    switch (_that) {
      case CardanoError_InvalidAddress() when invalidAddress != null:
        return invalidAddress(_that);
      case CardanoError_InvalidMnemonic() when invalidMnemonic != null:
        return invalidMnemonic(_that);
      case CardanoError_DerivationError() when derivationError != null:
        return derivationError(_that);
      case CardanoError_SerializationError() when serializationError != null:
        return serializationError(_that);
      case CardanoError_NetworkError() when networkError != null:
        return networkError(_that);
      case CardanoError_InvalidKey() when invalidKey != null:
        return invalidKey(_that);
      case CardanoError_CslError() when cslError != null:
        return cslError(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? invalidAddress,
    TResult Function(String field0)? invalidMnemonic,
    TResult Function(String field0)? derivationError,
    TResult Function(String field0)? serializationError,
    TResult Function(String field0)? networkError,
    TResult Function(String field0)? invalidKey,
    TResult Function(String field0)? cslError,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case CardanoError_InvalidAddress() when invalidAddress != null:
        return invalidAddress(_that.field0);
      case CardanoError_InvalidMnemonic() when invalidMnemonic != null:
        return invalidMnemonic(_that.field0);
      case CardanoError_DerivationError() when derivationError != null:
        return derivationError(_that.field0);
      case CardanoError_SerializationError() when serializationError != null:
        return serializationError(_that.field0);
      case CardanoError_NetworkError() when networkError != null:
        return networkError(_that.field0);
      case CardanoError_InvalidKey() when invalidKey != null:
        return invalidKey(_that.field0);
      case CardanoError_CslError() when cslError != null:
        return cslError(_that.field0);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) invalidAddress,
    required TResult Function(String field0) invalidMnemonic,
    required TResult Function(String field0) derivationError,
    required TResult Function(String field0) serializationError,
    required TResult Function(String field0) networkError,
    required TResult Function(String field0) invalidKey,
    required TResult Function(String field0) cslError,
  }) {
    final _that = this;
    switch (_that) {
      case CardanoError_InvalidAddress():
        return invalidAddress(_that.field0);
      case CardanoError_InvalidMnemonic():
        return invalidMnemonic(_that.field0);
      case CardanoError_DerivationError():
        return derivationError(_that.field0);
      case CardanoError_SerializationError():
        return serializationError(_that.field0);
      case CardanoError_NetworkError():
        return networkError(_that.field0);
      case CardanoError_InvalidKey():
        return invalidKey(_that.field0);
      case CardanoError_CslError():
        return cslError(_that.field0);
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? invalidAddress,
    TResult? Function(String field0)? invalidMnemonic,
    TResult? Function(String field0)? derivationError,
    TResult? Function(String field0)? serializationError,
    TResult? Function(String field0)? networkError,
    TResult? Function(String field0)? invalidKey,
    TResult? Function(String field0)? cslError,
  }) {
    final _that = this;
    switch (_that) {
      case CardanoError_InvalidAddress() when invalidAddress != null:
        return invalidAddress(_that.field0);
      case CardanoError_InvalidMnemonic() when invalidMnemonic != null:
        return invalidMnemonic(_that.field0);
      case CardanoError_DerivationError() when derivationError != null:
        return derivationError(_that.field0);
      case CardanoError_SerializationError() when serializationError != null:
        return serializationError(_that.field0);
      case CardanoError_NetworkError() when networkError != null:
        return networkError(_that.field0);
      case CardanoError_InvalidKey() when invalidKey != null:
        return invalidKey(_that.field0);
      case CardanoError_CslError() when cslError != null:
        return cslError(_that.field0);
      case _:
        return null;
    }
  }
}

/// @nodoc

class CardanoError_InvalidAddress extends CardanoError {
  const CardanoError_InvalidAddress(this.field0) : super._();

  @override
  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_InvalidAddressCopyWith<CardanoError_InvalidAddress>
      get copyWith => _$CardanoError_InvalidAddressCopyWithImpl<
          CardanoError_InvalidAddress>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_InvalidAddress &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.invalidAddress(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_InvalidAddressCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_InvalidAddressCopyWith(
          CardanoError_InvalidAddress value,
          $Res Function(CardanoError_InvalidAddress) _then) =
      _$CardanoError_InvalidAddressCopyWithImpl;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_InvalidAddressCopyWithImpl<$Res>
    implements $CardanoError_InvalidAddressCopyWith<$Res> {
  _$CardanoError_InvalidAddressCopyWithImpl(this._self, this._then);

  final CardanoError_InvalidAddress _self;
  final $Res Function(CardanoError_InvalidAddress) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_InvalidAddress(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class CardanoError_InvalidMnemonic extends CardanoError {
  const CardanoError_InvalidMnemonic(this.field0) : super._();

  @override
  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_InvalidMnemonicCopyWith<CardanoError_InvalidMnemonic>
      get copyWith => _$CardanoError_InvalidMnemonicCopyWithImpl<
          CardanoError_InvalidMnemonic>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_InvalidMnemonic &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.invalidMnemonic(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_InvalidMnemonicCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_InvalidMnemonicCopyWith(
          CardanoError_InvalidMnemonic value,
          $Res Function(CardanoError_InvalidMnemonic) _then) =
      _$CardanoError_InvalidMnemonicCopyWithImpl;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_InvalidMnemonicCopyWithImpl<$Res>
    implements $CardanoError_InvalidMnemonicCopyWith<$Res> {
  _$CardanoError_InvalidMnemonicCopyWithImpl(this._self, this._then);

  final CardanoError_InvalidMnemonic _self;
  final $Res Function(CardanoError_InvalidMnemonic) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_InvalidMnemonic(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class CardanoError_DerivationError extends CardanoError {
  const CardanoError_DerivationError(this.field0) : super._();

  @override
  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_DerivationErrorCopyWith<CardanoError_DerivationError>
      get copyWith => _$CardanoError_DerivationErrorCopyWithImpl<
          CardanoError_DerivationError>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_DerivationError &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.derivationError(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_DerivationErrorCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_DerivationErrorCopyWith(
          CardanoError_DerivationError value,
          $Res Function(CardanoError_DerivationError) _then) =
      _$CardanoError_DerivationErrorCopyWithImpl;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_DerivationErrorCopyWithImpl<$Res>
    implements $CardanoError_DerivationErrorCopyWith<$Res> {
  _$CardanoError_DerivationErrorCopyWithImpl(this._self, this._then);

  final CardanoError_DerivationError _self;
  final $Res Function(CardanoError_DerivationError) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_DerivationError(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class CardanoError_SerializationError extends CardanoError {
  const CardanoError_SerializationError(this.field0) : super._();

  @override
  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_SerializationErrorCopyWith<CardanoError_SerializationError>
      get copyWith => _$CardanoError_SerializationErrorCopyWithImpl<
          CardanoError_SerializationError>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_SerializationError &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.serializationError(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_SerializationErrorCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_SerializationErrorCopyWith(
          CardanoError_SerializationError value,
          $Res Function(CardanoError_SerializationError) _then) =
      _$CardanoError_SerializationErrorCopyWithImpl;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_SerializationErrorCopyWithImpl<$Res>
    implements $CardanoError_SerializationErrorCopyWith<$Res> {
  _$CardanoError_SerializationErrorCopyWithImpl(this._self, this._then);

  final CardanoError_SerializationError _self;
  final $Res Function(CardanoError_SerializationError) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_SerializationError(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class CardanoError_NetworkError extends CardanoError {
  const CardanoError_NetworkError(this.field0) : super._();

  @override
  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_NetworkErrorCopyWith<CardanoError_NetworkError> get copyWith =>
      _$CardanoError_NetworkErrorCopyWithImpl<CardanoError_NetworkError>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_NetworkError &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.networkError(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_NetworkErrorCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_NetworkErrorCopyWith(CardanoError_NetworkError value,
          $Res Function(CardanoError_NetworkError) _then) =
      _$CardanoError_NetworkErrorCopyWithImpl;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_NetworkErrorCopyWithImpl<$Res>
    implements $CardanoError_NetworkErrorCopyWith<$Res> {
  _$CardanoError_NetworkErrorCopyWithImpl(this._self, this._then);

  final CardanoError_NetworkError _self;
  final $Res Function(CardanoError_NetworkError) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_NetworkError(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class CardanoError_InvalidKey extends CardanoError {
  const CardanoError_InvalidKey(this.field0) : super._();

  @override
  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_InvalidKeyCopyWith<CardanoError_InvalidKey> get copyWith =>
      _$CardanoError_InvalidKeyCopyWithImpl<CardanoError_InvalidKey>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_InvalidKey &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.invalidKey(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_InvalidKeyCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_InvalidKeyCopyWith(CardanoError_InvalidKey value,
          $Res Function(CardanoError_InvalidKey) _then) =
      _$CardanoError_InvalidKeyCopyWithImpl;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_InvalidKeyCopyWithImpl<$Res>
    implements $CardanoError_InvalidKeyCopyWith<$Res> {
  _$CardanoError_InvalidKeyCopyWithImpl(this._self, this._then);

  final CardanoError_InvalidKey _self;
  final $Res Function(CardanoError_InvalidKey) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_InvalidKey(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class CardanoError_CslError extends CardanoError {
  const CardanoError_CslError(this.field0) : super._();

  @override
  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_CslErrorCopyWith<CardanoError_CslError> get copyWith =>
      _$CardanoError_CslErrorCopyWithImpl<CardanoError_CslError>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_CslError &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.cslError(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_CslErrorCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_CslErrorCopyWith(CardanoError_CslError value,
          $Res Function(CardanoError_CslError) _then) =
      _$CardanoError_CslErrorCopyWithImpl;
  @override
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_CslErrorCopyWithImpl<$Res>
    implements $CardanoError_CslErrorCopyWith<$Res> {
  _$CardanoError_CslErrorCopyWithImpl(this._self, this._then);

  final CardanoError_CslError _self;
  final $Res Function(CardanoError_CslError) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_CslError(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
