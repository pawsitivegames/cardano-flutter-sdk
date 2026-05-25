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
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is CardanoError);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'CardanoError()';
  }
}

/// @nodoc
class $CardanoErrorCopyWith<$Res> {
  $CardanoErrorCopyWith(CardanoError _, $Res Function(CardanoError) __);
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
    TResult Function(CardanoError_InvalidCbor value)? invalidCbor,
    TResult Function(CardanoError_CslError value)? cslError,
    TResult Function(CardanoError_InsufficientFunds value)? insufficientFunds,
    TResult Function(CardanoError_InsufficientAsset value)? insufficientAsset,
    TResult Function(CardanoError_DustChange value)? dustChange,
    TResult Function(CardanoError_CoinSelectionError value)? coinSelectionError,
    TResult Function(CardanoError_TxBuild value)? txBuild,
    TResult Function(CardanoError_InvalidParameter value)? invalidParameter,
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
      case CardanoError_InvalidCbor() when invalidCbor != null:
        return invalidCbor(_that);
      case CardanoError_CslError() when cslError != null:
        return cslError(_that);
      case CardanoError_InsufficientFunds() when insufficientFunds != null:
        return insufficientFunds(_that);
      case CardanoError_InsufficientAsset() when insufficientAsset != null:
        return insufficientAsset(_that);
      case CardanoError_DustChange() when dustChange != null:
        return dustChange(_that);
      case CardanoError_CoinSelectionError() when coinSelectionError != null:
        return coinSelectionError(_that);
      case CardanoError_TxBuild() when txBuild != null:
        return txBuild(_that);
      case CardanoError_InvalidParameter() when invalidParameter != null:
        return invalidParameter(_that);
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
    required TResult Function(CardanoError_InvalidCbor value) invalidCbor,
    required TResult Function(CardanoError_CslError value) cslError,
    required TResult Function(CardanoError_InsufficientFunds value)
        insufficientFunds,
    required TResult Function(CardanoError_InsufficientAsset value)
        insufficientAsset,
    required TResult Function(CardanoError_DustChange value) dustChange,
    required TResult Function(CardanoError_CoinSelectionError value)
        coinSelectionError,
    required TResult Function(CardanoError_TxBuild value) txBuild,
    required TResult Function(CardanoError_InvalidParameter value)
        invalidParameter,
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
      case CardanoError_InvalidCbor():
        return invalidCbor(_that);
      case CardanoError_CslError():
        return cslError(_that);
      case CardanoError_InsufficientFunds():
        return insufficientFunds(_that);
      case CardanoError_InsufficientAsset():
        return insufficientAsset(_that);
      case CardanoError_DustChange():
        return dustChange(_that);
      case CardanoError_CoinSelectionError():
        return coinSelectionError(_that);
      case CardanoError_TxBuild():
        return txBuild(_that);
      case CardanoError_InvalidParameter():
        return invalidParameter(_that);
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
    TResult? Function(CardanoError_InvalidCbor value)? invalidCbor,
    TResult? Function(CardanoError_CslError value)? cslError,
    TResult? Function(CardanoError_InsufficientFunds value)? insufficientFunds,
    TResult? Function(CardanoError_InsufficientAsset value)? insufficientAsset,
    TResult? Function(CardanoError_DustChange value)? dustChange,
    TResult? Function(CardanoError_CoinSelectionError value)?
        coinSelectionError,
    TResult? Function(CardanoError_TxBuild value)? txBuild,
    TResult? Function(CardanoError_InvalidParameter value)? invalidParameter,
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
      case CardanoError_InvalidCbor() when invalidCbor != null:
        return invalidCbor(_that);
      case CardanoError_CslError() when cslError != null:
        return cslError(_that);
      case CardanoError_InsufficientFunds() when insufficientFunds != null:
        return insufficientFunds(_that);
      case CardanoError_InsufficientAsset() when insufficientAsset != null:
        return insufficientAsset(_that);
      case CardanoError_DustChange() when dustChange != null:
        return dustChange(_that);
      case CardanoError_CoinSelectionError() when coinSelectionError != null:
        return coinSelectionError(_that);
      case CardanoError_TxBuild() when txBuild != null:
        return txBuild(_that);
      case CardanoError_InvalidParameter() when invalidParameter != null:
        return invalidParameter(_that);
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
    TResult Function(String field0)? invalidCbor,
    TResult Function(String field0)? cslError,
    TResult Function(BigInt neededLovelace, BigInt availableLovelace)?
        insufficientFunds,
    TResult Function(
            String policyId, String assetName, BigInt needed, BigInt available)?
        insufficientAsset,
    TResult Function(BigInt residualLovelace, BigInt minRequired)? dustChange,
    TResult Function(String field0)? coinSelectionError,
    TResult Function(String reason)? txBuild,
    TResult Function(String field, String reason)? invalidParameter,
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
      case CardanoError_InvalidCbor() when invalidCbor != null:
        return invalidCbor(_that.field0);
      case CardanoError_CslError() when cslError != null:
        return cslError(_that.field0);
      case CardanoError_InsufficientFunds() when insufficientFunds != null:
        return insufficientFunds(_that.neededLovelace, _that.availableLovelace);
      case CardanoError_InsufficientAsset() when insufficientAsset != null:
        return insufficientAsset(
            _that.policyId, _that.assetName, _that.needed, _that.available);
      case CardanoError_DustChange() when dustChange != null:
        return dustChange(_that.residualLovelace, _that.minRequired);
      case CardanoError_CoinSelectionError() when coinSelectionError != null:
        return coinSelectionError(_that.field0);
      case CardanoError_TxBuild() when txBuild != null:
        return txBuild(_that.reason);
      case CardanoError_InvalidParameter() when invalidParameter != null:
        return invalidParameter(_that.field, _that.reason);
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
    required TResult Function(String field0) invalidCbor,
    required TResult Function(String field0) cslError,
    required TResult Function(BigInt neededLovelace, BigInt availableLovelace)
        insufficientFunds,
    required TResult Function(
            String policyId, String assetName, BigInt needed, BigInt available)
        insufficientAsset,
    required TResult Function(BigInt residualLovelace, BigInt minRequired)
        dustChange,
    required TResult Function(String field0) coinSelectionError,
    required TResult Function(String reason) txBuild,
    required TResult Function(String field, String reason) invalidParameter,
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
      case CardanoError_InvalidCbor():
        return invalidCbor(_that.field0);
      case CardanoError_CslError():
        return cslError(_that.field0);
      case CardanoError_InsufficientFunds():
        return insufficientFunds(_that.neededLovelace, _that.availableLovelace);
      case CardanoError_InsufficientAsset():
        return insufficientAsset(
            _that.policyId, _that.assetName, _that.needed, _that.available);
      case CardanoError_DustChange():
        return dustChange(_that.residualLovelace, _that.minRequired);
      case CardanoError_CoinSelectionError():
        return coinSelectionError(_that.field0);
      case CardanoError_TxBuild():
        return txBuild(_that.reason);
      case CardanoError_InvalidParameter():
        return invalidParameter(_that.field, _that.reason);
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
    TResult? Function(String field0)? invalidCbor,
    TResult? Function(String field0)? cslError,
    TResult? Function(BigInt neededLovelace, BigInt availableLovelace)?
        insufficientFunds,
    TResult? Function(
            String policyId, String assetName, BigInt needed, BigInt available)?
        insufficientAsset,
    TResult? Function(BigInt residualLovelace, BigInt minRequired)? dustChange,
    TResult? Function(String field0)? coinSelectionError,
    TResult? Function(String reason)? txBuild,
    TResult? Function(String field, String reason)? invalidParameter,
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
      case CardanoError_InvalidCbor() when invalidCbor != null:
        return invalidCbor(_that.field0);
      case CardanoError_CslError() when cslError != null:
        return cslError(_that.field0);
      case CardanoError_InsufficientFunds() when insufficientFunds != null:
        return insufficientFunds(_that.neededLovelace, _that.availableLovelace);
      case CardanoError_InsufficientAsset() when insufficientAsset != null:
        return insufficientAsset(
            _that.policyId, _that.assetName, _that.needed, _that.available);
      case CardanoError_DustChange() when dustChange != null:
        return dustChange(_that.residualLovelace, _that.minRequired);
      case CardanoError_CoinSelectionError() when coinSelectionError != null:
        return coinSelectionError(_that.field0);
      case CardanoError_TxBuild() when txBuild != null:
        return txBuild(_that.reason);
      case CardanoError_InvalidParameter() when invalidParameter != null:
        return invalidParameter(_that.field, _that.reason);
      case _:
        return null;
    }
  }
}

/// @nodoc

class CardanoError_InvalidAddress extends CardanoError {
  const CardanoError_InvalidAddress(this.field0) : super._();

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
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

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
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

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
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

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
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

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
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

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
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

class CardanoError_InvalidCbor extends CardanoError {
  const CardanoError_InvalidCbor(this.field0) : super._();

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_InvalidCborCopyWith<CardanoError_InvalidCbor> get copyWith =>
      _$CardanoError_InvalidCborCopyWithImpl<CardanoError_InvalidCbor>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_InvalidCbor &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.invalidCbor(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_InvalidCborCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_InvalidCborCopyWith(CardanoError_InvalidCbor value,
          $Res Function(CardanoError_InvalidCbor) _then) =
      _$CardanoError_InvalidCborCopyWithImpl;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_InvalidCborCopyWithImpl<$Res>
    implements $CardanoError_InvalidCborCopyWith<$Res> {
  _$CardanoError_InvalidCborCopyWithImpl(this._self, this._then);

  final CardanoError_InvalidCbor _self;
  final $Res Function(CardanoError_InvalidCbor) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_InvalidCbor(
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

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
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

/// @nodoc

class CardanoError_InsufficientFunds extends CardanoError {
  const CardanoError_InsufficientFunds(
      {required this.neededLovelace, required this.availableLovelace})
      : super._();

  final BigInt neededLovelace;
  final BigInt availableLovelace;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_InsufficientFundsCopyWith<CardanoError_InsufficientFunds>
      get copyWith => _$CardanoError_InsufficientFundsCopyWithImpl<
          CardanoError_InsufficientFunds>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_InsufficientFunds &&
            (identical(other.neededLovelace, neededLovelace) ||
                other.neededLovelace == neededLovelace) &&
            (identical(other.availableLovelace, availableLovelace) ||
                other.availableLovelace == availableLovelace));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, neededLovelace, availableLovelace);

  @override
  String toString() {
    return 'CardanoError.insufficientFunds(neededLovelace: $neededLovelace, availableLovelace: $availableLovelace)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_InsufficientFundsCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_InsufficientFundsCopyWith(
          CardanoError_InsufficientFunds value,
          $Res Function(CardanoError_InsufficientFunds) _then) =
      _$CardanoError_InsufficientFundsCopyWithImpl;
  @useResult
  $Res call({BigInt neededLovelace, BigInt availableLovelace});
}

/// @nodoc
class _$CardanoError_InsufficientFundsCopyWithImpl<$Res>
    implements $CardanoError_InsufficientFundsCopyWith<$Res> {
  _$CardanoError_InsufficientFundsCopyWithImpl(this._self, this._then);

  final CardanoError_InsufficientFunds _self;
  final $Res Function(CardanoError_InsufficientFunds) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? neededLovelace = null,
    Object? availableLovelace = null,
  }) {
    return _then(CardanoError_InsufficientFunds(
      neededLovelace: null == neededLovelace
          ? _self.neededLovelace
          : neededLovelace // ignore: cast_nullable_to_non_nullable
              as BigInt,
      availableLovelace: null == availableLovelace
          ? _self.availableLovelace
          : availableLovelace // ignore: cast_nullable_to_non_nullable
              as BigInt,
    ));
  }
}

/// @nodoc

class CardanoError_InsufficientAsset extends CardanoError {
  const CardanoError_InsufficientAsset(
      {required this.policyId,
      required this.assetName,
      required this.needed,
      required this.available})
      : super._();

  final String policyId;
  final String assetName;
  final BigInt needed;
  final BigInt available;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_InsufficientAssetCopyWith<CardanoError_InsufficientAsset>
      get copyWith => _$CardanoError_InsufficientAssetCopyWithImpl<
          CardanoError_InsufficientAsset>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_InsufficientAsset &&
            (identical(other.policyId, policyId) ||
                other.policyId == policyId) &&
            (identical(other.assetName, assetName) ||
                other.assetName == assetName) &&
            (identical(other.needed, needed) || other.needed == needed) &&
            (identical(other.available, available) ||
                other.available == available));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, policyId, assetName, needed, available);

  @override
  String toString() {
    return 'CardanoError.insufficientAsset(policyId: $policyId, assetName: $assetName, needed: $needed, available: $available)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_InsufficientAssetCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_InsufficientAssetCopyWith(
          CardanoError_InsufficientAsset value,
          $Res Function(CardanoError_InsufficientAsset) _then) =
      _$CardanoError_InsufficientAssetCopyWithImpl;
  @useResult
  $Res call(
      {String policyId, String assetName, BigInt needed, BigInt available});
}

/// @nodoc
class _$CardanoError_InsufficientAssetCopyWithImpl<$Res>
    implements $CardanoError_InsufficientAssetCopyWith<$Res> {
  _$CardanoError_InsufficientAssetCopyWithImpl(this._self, this._then);

  final CardanoError_InsufficientAsset _self;
  final $Res Function(CardanoError_InsufficientAsset) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? policyId = null,
    Object? assetName = null,
    Object? needed = null,
    Object? available = null,
  }) {
    return _then(CardanoError_InsufficientAsset(
      policyId: null == policyId
          ? _self.policyId
          : policyId // ignore: cast_nullable_to_non_nullable
              as String,
      assetName: null == assetName
          ? _self.assetName
          : assetName // ignore: cast_nullable_to_non_nullable
              as String,
      needed: null == needed
          ? _self.needed
          : needed // ignore: cast_nullable_to_non_nullable
              as BigInt,
      available: null == available
          ? _self.available
          : available // ignore: cast_nullable_to_non_nullable
              as BigInt,
    ));
  }
}

/// @nodoc

class CardanoError_DustChange extends CardanoError {
  const CardanoError_DustChange(
      {required this.residualLovelace, required this.minRequired})
      : super._();

  final BigInt residualLovelace;
  final BigInt minRequired;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_DustChangeCopyWith<CardanoError_DustChange> get copyWith =>
      _$CardanoError_DustChangeCopyWithImpl<CardanoError_DustChange>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_DustChange &&
            (identical(other.residualLovelace, residualLovelace) ||
                other.residualLovelace == residualLovelace) &&
            (identical(other.minRequired, minRequired) ||
                other.minRequired == minRequired));
  }

  @override
  int get hashCode => Object.hash(runtimeType, residualLovelace, minRequired);

  @override
  String toString() {
    return 'CardanoError.dustChange(residualLovelace: $residualLovelace, minRequired: $minRequired)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_DustChangeCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_DustChangeCopyWith(CardanoError_DustChange value,
          $Res Function(CardanoError_DustChange) _then) =
      _$CardanoError_DustChangeCopyWithImpl;
  @useResult
  $Res call({BigInt residualLovelace, BigInt minRequired});
}

/// @nodoc
class _$CardanoError_DustChangeCopyWithImpl<$Res>
    implements $CardanoError_DustChangeCopyWith<$Res> {
  _$CardanoError_DustChangeCopyWithImpl(this._self, this._then);

  final CardanoError_DustChange _self;
  final $Res Function(CardanoError_DustChange) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? residualLovelace = null,
    Object? minRequired = null,
  }) {
    return _then(CardanoError_DustChange(
      residualLovelace: null == residualLovelace
          ? _self.residualLovelace
          : residualLovelace // ignore: cast_nullable_to_non_nullable
              as BigInt,
      minRequired: null == minRequired
          ? _self.minRequired
          : minRequired // ignore: cast_nullable_to_non_nullable
              as BigInt,
    ));
  }
}

/// @nodoc

class CardanoError_CoinSelectionError extends CardanoError {
  const CardanoError_CoinSelectionError(this.field0) : super._();

  final String field0;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_CoinSelectionErrorCopyWith<CardanoError_CoinSelectionError>
      get copyWith => _$CardanoError_CoinSelectionErrorCopyWithImpl<
          CardanoError_CoinSelectionError>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_CoinSelectionError &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CardanoError.coinSelectionError(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_CoinSelectionErrorCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_CoinSelectionErrorCopyWith(
          CardanoError_CoinSelectionError value,
          $Res Function(CardanoError_CoinSelectionError) _then) =
      _$CardanoError_CoinSelectionErrorCopyWithImpl;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$CardanoError_CoinSelectionErrorCopyWithImpl<$Res>
    implements $CardanoError_CoinSelectionErrorCopyWith<$Res> {
  _$CardanoError_CoinSelectionErrorCopyWithImpl(this._self, this._then);

  final CardanoError_CoinSelectionError _self;
  final $Res Function(CardanoError_CoinSelectionError) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CardanoError_CoinSelectionError(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class CardanoError_TxBuild extends CardanoError {
  const CardanoError_TxBuild({required this.reason}) : super._();

  final String reason;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_TxBuildCopyWith<CardanoError_TxBuild> get copyWith =>
      _$CardanoError_TxBuildCopyWithImpl<CardanoError_TxBuild>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_TxBuild &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @override
  String toString() {
    return 'CardanoError.txBuild(reason: $reason)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_TxBuildCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_TxBuildCopyWith(CardanoError_TxBuild value,
          $Res Function(CardanoError_TxBuild) _then) =
      _$CardanoError_TxBuildCopyWithImpl;
  @useResult
  $Res call({String reason});
}

/// @nodoc
class _$CardanoError_TxBuildCopyWithImpl<$Res>
    implements $CardanoError_TxBuildCopyWith<$Res> {
  _$CardanoError_TxBuildCopyWithImpl(this._self, this._then);

  final CardanoError_TxBuild _self;
  final $Res Function(CardanoError_TxBuild) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? reason = null,
  }) {
    return _then(CardanoError_TxBuild(
      reason: null == reason
          ? _self.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class CardanoError_InvalidParameter extends CardanoError {
  const CardanoError_InvalidParameter(
      {required this.field, required this.reason})
      : super._();

  final String field;
  final String reason;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CardanoError_InvalidParameterCopyWith<CardanoError_InvalidParameter>
      get copyWith => _$CardanoError_InvalidParameterCopyWithImpl<
          CardanoError_InvalidParameter>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CardanoError_InvalidParameter &&
            (identical(other.field, field) || other.field == field) &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field, reason);

  @override
  String toString() {
    return 'CardanoError.invalidParameter(field: $field, reason: $reason)';
  }
}

/// @nodoc
abstract mixin class $CardanoError_InvalidParameterCopyWith<$Res>
    implements $CardanoErrorCopyWith<$Res> {
  factory $CardanoError_InvalidParameterCopyWith(
          CardanoError_InvalidParameter value,
          $Res Function(CardanoError_InvalidParameter) _then) =
      _$CardanoError_InvalidParameterCopyWithImpl;
  @useResult
  $Res call({String field, String reason});
}

/// @nodoc
class _$CardanoError_InvalidParameterCopyWithImpl<$Res>
    implements $CardanoError_InvalidParameterCopyWith<$Res> {
  _$CardanoError_InvalidParameterCopyWithImpl(this._self, this._then);

  final CardanoError_InvalidParameter _self;
  final $Res Function(CardanoError_InvalidParameter) _then;

  /// Create a copy of CardanoError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field = null,
    Object? reason = null,
  }) {
    return _then(CardanoError_InvalidParameter(
      field: null == field
          ? _self.field
          : field // ignore: cast_nullable_to_non_nullable
              as String,
      reason: null == reason
          ? _self.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
