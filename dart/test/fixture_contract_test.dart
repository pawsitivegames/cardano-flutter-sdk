// Data-contract gates for checked-in interoperability fixtures.
//
// These tests deliberately validate the shapes consumed by the conformance and
// cross-wallet tests. JSON parseability alone is not enough: a typo in an op,
// an odd-length hex string, or an empty external-fixture list can otherwise
// move a meaningful interop guarantee out of the test surface.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _goldenPath = 'test/conformance/golden_cbor.json';
const _crossWalletPath = 'test/fixtures/cross_wallet_signatures.json';

const _goldenFields = {'id', 'category', 'op', 'input', 'expected'};
const _categories = {'address', 'value', 'plutus', 'witness', 'cose'};
const _ops = {
  'keyDerivation',
  'deriveAddress',
  'computeBaseAddress',
  'addressToHex',
  'valueToCbor',
  'plutusInt',
  'plutusBytes',
  'plutusConstr',
  'plutusList',
  'witnessSet',
  'signData',
  'verifyData',
  'signMessage',
};

const _crossWalletSchemaFields = {
  'wallet',
  'network',
  'message',
  'payloadHex',
  'addressHex',
  'signature',
  'key',
  'expectAccept',
};

void main() {
  test('golden vectors satisfy their versioned fixture contract', () {
    final decoded = jsonDecode(File(_goldenPath).readAsStringSync());
    expect(decoded, isA<List<dynamic>>());

    final records = decoded as List<dynamic>;
    expect(records, isNotEmpty);
    final errors = <String>[];
    final ids = <String>{};

    for (var index = 0; index < records.length; index++) {
      final value = records[index];
      final prefix = 'golden[$index]';
      if (value is! Map) {
        errors.add('$prefix must be an object');
        continue;
      }
      final record = Map<String, dynamic>.from(value);
      _expectExactKeys(record, _goldenFields, prefix, errors);

      final id = record['id'];
      if (id is! String || id.trim().isEmpty) {
        errors.add('$prefix.id must be a non-empty string');
      } else if (!ids.add(id)) {
        errors.add('$prefix.id duplicates "$id"');
      }

      final category = record['category'];
      if (category is! String || !_categories.contains(category)) {
        errors.add('$prefix.category is not an allowed category');
      }
      final op = record['op'];
      if (op is! String || !_ops.contains(op)) {
        errors.add('$prefix.op is not an allowed operation');
        continue;
      }
      final input = record['input'];
      if (input is! Map) {
        errors.add('$prefix.input must be an object');
        continue;
      }
      final inputMap = Map<String, dynamic>.from(input);
      _validateGoldenInput(op, inputMap, prefix, errors);

      if (record['expected'] is! String ||
          (record['expected'] as String).isEmpty) {
        errors.add('$prefix.expected must be a non-empty string');
      }
    }

    expect(errors, isEmpty, reason: errors.join('\n'));
  });

  test('cross-wallet fixture retains schema, provenance, and active coverage',
      () {
    final decoded = jsonDecode(File(_crossWalletPath).readAsStringSync());
    expect(decoded, isA<Map<String, dynamic>>());
    final root = Map<String, dynamic>.from(decoded as Map);
    final errors = <String>[];

    for (final required in const {'_README', '_schema', 'signatures'}) {
      if (!root.containsKey(required)) errors.add('root missing $required');
    }
    if (root['_README'] is! String ||
        (root['_README'] as String).trim().isEmpty) {
      errors.add('root._README must document the fixture provenance');
    }
    final schema = root['_schema'];
    if (schema is! Map) {
      errors.add('root._schema must be an object');
    } else {
      final schemaMap = Map<String, dynamic>.from(schema);
      if (!schemaMap.keys.toSet().containsAll({
        'wallet',
        'network',
        'message',
        'payloadHex',
        'signature',
        'key',
      })) {
        errors.add('root._schema omits a documented required field');
      }
    }

    final signatures = root['signatures'];
    if (signatures is! List || signatures.isEmpty) {
      errors
          .add('root.signatures must retain at least one real wallet fixture');
    } else {
      for (var index = 0; index < signatures.length; index++) {
        final value = signatures[index];
        final prefix = 'signatures[$index]';
        if (value is! Map) {
          errors.add('$prefix must be an object');
          continue;
        }
        final fixture = Map<String, dynamic>.from(value);
        _expectSubsetKeys(fixture, _crossWalletSchemaFields, prefix, errors);
        for (final field in const {
          'wallet',
          'network',
          'message',
          'payloadHex',
          'signature',
          'key',
        }) {
          if (!fixture.containsKey(field)) {
            errors.add('$prefix.$field is required');
          }
        }
        for (final field in const {'wallet', 'message', 'signature', 'key'}) {
          final item = fixture[field];
          if (item is! String || item.trim().isEmpty) {
            errors.add('$prefix.$field must be a non-empty string');
          }
        }
        if (fixture['network'] is! String ||
            !{'testnet', 'mainnet'}.contains(fixture['network'])) {
          errors.add('$prefix.network must be testnet or mainnet');
        }
        _validateHex(fixture['payloadHex'], '$prefix.payloadHex', errors);
        if (fixture.containsKey('addressHex')) {
          _validateHex(fixture['addressHex'], '$prefix.addressHex', errors);
        }
        _validateHex(fixture['signature'], '$prefix.signature', errors);
        _validateHex(fixture['key'], '$prefix.key', errors);
        if (fixture.containsKey('expectAccept') &&
            fixture['expectAccept'] is! bool) {
          errors.add('$prefix.expectAccept must be boolean when present');
        }
      }
    }

    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}

void _validateGoldenInput(
  String op,
  Map<String, dynamic> input,
  String prefix,
  List<String> errors,
) {
  final required = <String, Set<String>>{
    'keyDerivation': {'mnemonic', 'passphrase', 'accountIndex', 'isTestnet'},
    'deriveAddress': {'accountKey', 'role', 'index', 'networkId'},
    'computeBaseAddress': {
      'paymentKeyHashHex',
      'stakeKeyHashHex',
      'networkId',
    },
    'addressToHex': {'addressBech32'},
    'valueToCbor': {'coin', 'assets'},
    'plutusInt': {'n'},
    'plutusBytes': {'hexData'},
    'plutusConstr': {'constructor', 'fieldsCborHex'},
    'plutusList': {'itemsCborHex'},
    'witnessSet': {'witnesses'},
    'signData': {'addressHex', 'payloadHex', 'signingKeyBech32'},
    'verifyData': {'signature', 'key'},
    'signMessage': {'message', 'signingKeyBech32'},
  }[op]!;
  final allowed = {...required};
  if (op == 'verifyData') {
    allowed.addAll({'expectedPayloadHex', 'expectedAddressHex'});
  }
  if (op == 'verifyData') {
    _expectSubsetKeys(input, allowed, '$prefix.input', errors);
  } else {
    _expectExactKeys(input, allowed, '$prefix.input', errors);
  }
  for (final field in required) {
    if (!input.containsKey(field))
      errors.add('$prefix.input.$field is required');
  }

  switch (op) {
    case 'keyDerivation':
      _nonEmptyString(input['mnemonic'], '$prefix.input.mnemonic', errors);
      _string(input['passphrase'], '$prefix.input.passphrase', errors);
      _nonNegativeInt(
          input['accountIndex'], '$prefix.input.accountIndex', errors);
      if (input['isTestnet'] is! bool) {
        errors.add('$prefix.input.isTestnet must be boolean');
      }
    case 'deriveAddress':
      _nonEmptyString(input['accountKey'], '$prefix.input.accountKey', errors);
      _boundedInt(input['role'], '$prefix.input.role', 0, 2, errors);
      _nonNegativeInt(input['index'], '$prefix.input.index', errors);
      _boundedInt(input['networkId'], '$prefix.input.networkId', 0, 15, errors);
    case 'computeBaseAddress':
      _validateHex(
          input['paymentKeyHashHex'], '$prefix.input.paymentKeyHashHex', errors,
          exactBytes: 28);
      _validateHex(
          input['stakeKeyHashHex'], '$prefix.input.stakeKeyHashHex', errors,
          exactBytes: 28);
      _boundedInt(input['networkId'], '$prefix.input.networkId', 0, 15, errors);
    case 'addressToHex':
      _nonEmptyString(
          input['addressBech32'], '$prefix.input.addressBech32', errors);
    case 'valueToCbor':
      _decimalString(input['coin'], '$prefix.input.coin', errors,
          nonNegative: true);
      final assets = input['assets'];
      if (assets is! List) {
        errors.add('$prefix.input.assets must be a list');
      } else {
        for (var index = 0; index < assets.length; index++) {
          final item = assets[index];
          final assetPrefix = '$prefix.input.assets[$index]';
          if (item is! Map) {
            errors.add('$assetPrefix must be an object');
            continue;
          }
          final asset = Map<String, dynamic>.from(item);
          _expectExactKeys(asset, {'policyId', 'assetName', 'quantity'},
              assetPrefix, errors);
          _validateHex(asset['policyId'], '$assetPrefix.policyId', errors,
              exactBytes: 28);
          _validateHex(asset['assetName'], '$assetPrefix.assetName', errors);
          _decimalString(asset['quantity'], '$assetPrefix.quantity', errors,
              nonNegative: true);
        }
      }
    case 'plutusInt':
      _decimalString(input['n'], '$prefix.input.n', errors);
    case 'plutusBytes':
      _validateHex(input['hexData'], '$prefix.input.hexData', errors);
    case 'plutusConstr':
      _decimalString(input['constructor'], '$prefix.input.constructor', errors,
          nonNegative: true);
      _validateHexList(
          input['fieldsCborHex'], '$prefix.input.fieldsCborHex', errors);
    case 'plutusList':
      _validateHexList(
          input['itemsCborHex'], '$prefix.input.itemsCborHex', errors);
    case 'witnessSet':
      final witnesses = input['witnesses'];
      if (witnesses is! List) {
        errors.add('$prefix.input.witnesses must be a list');
      } else {
        for (var index = 0; index < witnesses.length; index++) {
          final item = witnesses[index];
          final witnessPrefix = '$prefix.input.witnesses[$index]';
          if (item is! Map) {
            errors.add('$witnessPrefix must be an object');
            continue;
          }
          final witness = Map<String, dynamic>.from(item);
          _expectExactKeys(
              witness, {'vkeyHex', 'signatureHex'}, witnessPrefix, errors);
          _validateHex(witness['vkeyHex'], '$witnessPrefix.vkeyHex', errors,
              exactBytes: 32);
          _validateHex(
              witness['signatureHex'], '$witnessPrefix.signatureHex', errors,
              exactBytes: 64);
        }
      }
    case 'signData':
      _validateHex(input['addressHex'], '$prefix.input.addressHex', errors);
      _validateHex(input['payloadHex'], '$prefix.input.payloadHex', errors);
      _nonEmptyString(
          input['signingKeyBech32'], '$prefix.input.signingKeyBech32', errors);
    case 'verifyData':
      _validateHex(input['signature'], '$prefix.input.signature', errors);
      _validateHex(input['key'], '$prefix.input.key', errors);
      if (input.containsKey('expectedPayloadHex')) {
        _validateHex(input['expectedPayloadHex'],
            '$prefix.input.expectedPayloadHex', errors);
      }
      if (input.containsKey('expectedAddressHex')) {
        _validateHex(input['expectedAddressHex'],
            '$prefix.input.expectedAddressHex', errors);
      }
    case 'signMessage':
      _nonEmptyString(input['message'], '$prefix.input.message', errors);
      _nonEmptyString(
          input['signingKeyBech32'], '$prefix.input.signingKeyBech32', errors);
  }
}

void _expectExactKeys(
  Map<String, dynamic> value,
  Set<String> expected,
  String prefix,
  List<String> errors,
) {
  final actual = value.keys.toSet();
  for (final key in expected.difference(actual)) {
    errors.add('$prefix is missing $key');
  }
  for (final key in actual.difference(expected)) {
    errors.add('$prefix has unexpected field $key');
  }
}

void _expectSubsetKeys(
  Map<String, dynamic> value,
  Set<String> allowed,
  String prefix,
  List<String> errors,
) {
  for (final key in value.keys.toSet().difference(allowed)) {
    errors.add('$prefix has unexpected field $key');
  }
}

void _string(dynamic value, String path, List<String> errors) {
  if (value is! String) errors.add('$path must be a string');
}

void _nonEmptyString(dynamic value, String path, List<String> errors) {
  if (value is! String || value.trim().isEmpty) {
    errors.add('$path must be a non-empty string');
  }
}

void _nonNegativeInt(dynamic value, String path, List<String> errors) {
  if (value is! int || value < 0)
    errors.add('$path must be a non-negative int');
}

void _boundedInt(
  dynamic value,
  String path,
  int min,
  int max,
  List<String> errors,
) {
  if (value is! int || value < min || value > max) {
    errors.add('$path must be an int from $min through $max');
  }
}

void _decimalString(
  dynamic value,
  String path,
  List<String> errors, {
  bool nonNegative = false,
}) {
  if (value is! String ||
      !RegExp(nonNegative ? r'^[0-9]+$' : r'^-?[0-9]+$').hasMatch(value)) {
    errors.add('$path must be a decimal string');
  }
}

void _validateHex(
  dynamic value,
  String path,
  List<String> errors, {
  int? exactBytes,
}) {
  if (value is! String ||
      value.length.isOdd ||
      !RegExp(r'^[0-9a-f]*$').hasMatch(value)) {
    errors.add('$path must be lowercase even-length hexadecimal');
    return;
  }
  if (exactBytes != null && value.length != exactBytes * 2) {
    errors.add('$path must encode exactly $exactBytes bytes');
  }
}

void _validateHexList(dynamic value, String path, List<String> errors) {
  if (value is! List) {
    errors.add('$path must be a list');
    return;
  }
  for (var index = 0; index < value.length; index++) {
    _validateHex(value[index], '$path[$index]', errors);
  }
}
