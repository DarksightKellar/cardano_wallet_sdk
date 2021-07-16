// import 'dart:math';

import 'package:hex/hex.dart';
import 'dart:convert';
import 'package:pinenacl/digests.dart';
import 'package:pinenacl/encoding.dart';
// import 'package:quiver/strings.dart';

class CurrencyAsset {
  /// unique ID for this asset (i.e. policyId+assetName)
  final String assetId;

  /// Policy ID of the asset. Blank if not set (only for ADA).
  final String policyId;

  /// Hex-encoded asset name of the asset
  final String assetName;

  /// human-readable version of assetName or empty string
  final String name;

  /// CIP14 based user-facing fingerprint
  final String fingerprint;

  /// Current asset quantity
  final String quantity;

  /// ID of the initial minting transaction
  final String initialMintTxHash;

  final CurrencyAssetMetadata? metadata;

  CurrencyAsset({
    required this.policyId,
    required this.assetName,
    String? fingerprint,
    required this.quantity,
    required this.initialMintTxHash,
    this.metadata,
  })  : this.assetId = '$policyId$assetName',
        this.name = hex2str.encode(assetName), //if assetName is not hex, this will usualy fail
        this.fingerprint = fingerprint ?? calculateFingerprint(policyId: policyId, assetNameHex: assetName);

  bool get isNativeToken => assetId != lovelaceHex;
  bool get isADA => assetId == lovelaceHex;

  /// return first non-null match from: ticker, metadata.name, name
  String get symbol => metadata?.ticker ?? metadata?.name ?? name;

  @override
  String toString() =>
      "CurrencyAsset(policyId: $policyId assetName: $assetName fingerprint: $fingerprint quantity: $quantity initialMintTxHash: $initialMintTxHash, metadata: $metadata)";
}

final lovelaceHex = str2hex.encode('lovelace');
final lovelaceAssetId = lovelaceHex;

class CurrencyAssetMetadata {
  /// Asset name
  final String name;

  /// Asset description
  final String description;

  final String? ticker;

  /// Asset website
  final String? url;

  /// Base64 encoded logo of the asset
  final String? logo;

  /// Number of decimals in currency. ADA has 6. Default is 0.
  final int decimals;

  CurrencyAssetMetadata({required this.name, required this.description, this.ticker, this.url, this.logo, this.decimals = 0});
  @override
  String toString() => "CurrencyAssetMetadata(name: $name ticker: $ticker url: $url description: $description hasLogo: ${logo != null})";
}

///
/// Pseudo ADA asset instance allows principal asset to be treated like other native tokens.
/// Blockfrost returns 'lovelace' as the currency unit, whereas all other native tokens are identified by their assetId, a hex string.
/// For consistency, 'lovelace' unit values must be converted to lovelaceHex strings.
///
final lovelacePseudoAsset = CurrencyAsset(
  policyId: '',
  assetName: lovelaceHex,
  quantity: '45000000000', //max
  initialMintTxHash: '',
  metadata: CurrencyAssetMetadata(
    name: 'Cardano',
    description: 'Principal currency of Cardano',
    ticker: 'ADA',
    url: 'https://cardano.org',
    logo: null,
    decimals: 6,
  ),
);

final Codec<String, String> str2hex = utf8.fuse(HEX);
final Codec<String, String> hex2str = str2hex.inverted;

///
List<int> blake2bHash(List<int> stringBytes, {required int digestSize}) =>
    Hash.blake2b(Uint8List.fromList(stringBytes), digestSize: digestSize);

List<int> blake2bHash160(List<int> stringBytes) => blake2bHash(stringBytes, digestSize: 20);

List<int> blake2bHash224(List<int> stringBytes) => blake2bHash(stringBytes, digestSize: 28);

List<int> blake2bHash256(List<int> stringBytes) => blake2bHash(stringBytes, digestSize: 32);

/// given a asset policyId and an assetName in hex, generate a bech32 asset fingerprint
String calculateFingerprint({required String policyId, required String assetNameHex, String hrp = 'asset'}) {
  //final assetNameHex = str2hex.encode(assetName);
  final assetId = '$policyId$assetNameHex';
  //print("assetId: $assetId");
  final assetIdBytes = HEX.decode(assetId);
  //print(b2s(assetIdBytes, prefix: 'assetIdBytes'));
  final List<int> hashBytes = blake2bHash160(assetIdBytes);
  //print(b2s(hashBytes, prefix: 'hashBytes'));
  final List<int> fiveBitArray = convertBits(hashBytes, 8, 5, false);
  //print(b2s(fiveBitArray, prefix: 'fiveBitArray'));
  return bech32.encode(Bech32(hrp, fiveBitArray));
}

/// Dump byte array. Example: bytes[20]: 244,155,227,187,150,186,199,61,202,241,76,208,46,192,219,56,241,103,253,67
String b2s(List<int> bytes, {String prefix = 'bytes'}) => "$prefix[${bytes.length}]: ${bytes.join(',')}";

List<int> convertBits(List<int> data, int fromWidth, int toWidth, bool pad) {
  int acc = 0;
  int bits = 0;
  int maxv = (1 << toWidth) - 1;
  List<int> ret = [];

  for (int i = 0; i < data.length; i++) {
    int value = data[i] & 0xff;
    if (value < 0 || value >> fromWidth != 0) {
      throw new FormatException("input data bit-width exceeds $fromWidth: $value");
    }
    acc = (acc << fromWidth) | value;
    bits += fromWidth;
    while (bits >= toWidth) {
      bits -= toWidth;
      ret.add((acc >> bits) & maxv);
    }
  }

  if (pad) {
    if (bits > 0) {
      ret.add((acc << (toWidth - bits)) & maxv);
    } else if (bits >= fromWidth || ((acc << (toWidth - bits)) & maxv) != 0) {
      throw new FormatException("input data bit-width exceeds $fromWidth: $bits");
    }
  }

  return ret;
}