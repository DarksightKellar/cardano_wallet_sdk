// Copyright 2021 Richard Easterling
// SPDX-License-Identifier: Apache-2.0

import 'package:bip32_ed25519/api.dart';
import '../address/shelley_address.dart';
import '../crypto/mnemonic.dart';
import '../crypto/mnemonic_english.dart';
// import '../transaction/model/bc_abstract.dart';
import '../crypto/shelley_key_derivation.dart';
import '../network/network_id.dart';
import '../transaction/model/bc_pointer.dart';
import '../transaction/model/bc_scripts.dart';
import './derivation_chain.dart';

///
/// These classes implement the Cardano version of HD (Hierarchical Deterministic)
/// Wallets which are used to generate a tree of cryptographic keys and addresses
/// from a single seed or master key in a reproducable way accross wallet vendors.
///
/// HdMaster holds the master key allowing it to create any other type of account:
/// ```
///   HdAccount account = HdMaster.mnemonic(['head', 'guard',...]).account();
///   HdAudit audit = HdMaster.mnemonic(['head', 'guard',...]).audit();
/// ```
/// The HD heiarchy only generates keys and addresses, it is not aware of block
/// chain transactions or balances.
///
/// The Cardano CIP1852 adoption of the BIP32 tree path is as follows:
/// ```
///     m / 1852' / 1815' / account' / role / index
/// ```

///
/// All HD Wallet use-cases are (or will eventualy be) supported as specified here:
///
/// https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki#use-cases
///
enum HdUseCase {
  fullWalletSharing('m'),
  audits('N(m/*)'),
  perOfficeBalances("m/i'"),
  recurrentBToBTx("N(m/i'/0)"),
  unsecureMoneyReceiver("N(m/i'/0)");

  const HdUseCase(this.expression);
  final String expression;
}

///
/// Base Account class specifies a use-case and Network.
///
abstract class HdAbstract {
  HdUseCase get useCase;
  Networks get network;
}

///
/// The Legacy interface supports both Shelley or Byron addresses.
///
abstract class HdLegacyReceiver {
  AbstractAddress receiveAddress({int index = 0});
}

///
/// AddressReceiver is the simplest possible Account, containing a collection
/// of addresses (Shelley or Byron) that can receive Cardano assets.
///
class HdAddressReceiver extends HdAbstract implements HdLegacyReceiver {
  @override
  final HdUseCase useCase = HdUseCase.unsecureMoneyReceiver;
  @override
  final Networks network;
  final List<AbstractAddress> receiveAddresses;

  HdAddressReceiver({required this.receiveAddresses})
      : network = _extractNetwork(receiveAddresses) {
    if (receiveAddresses.isEmpty) {
      throw InvalidAccountError('at least one address must be provided');
    }
  }

  @override
  AbstractAddress receiveAddress({int index = 0}) => receiveAddresses[index];

  static Networks _extractNetwork(List<AbstractAddress> receiveAddresses) {
    final network = receiveAddresses[0].network;
    for (AbstractAddress addr in receiveAddresses) {
      if (addr.network != network) {
        throw InvalidAccountError(
            "Can't have mainnet and testnet addresses in the same account: $receiveAddresses");
      }
    }
    return network;
  }
}

///
/// Generates addresses.
///
abstract class HdAddressGenerator extends HdAbstract {
  ShelleyAddress baseAddress({int index = 0});
  ShelleyAddress changeAddress({int index = 0});
  ShelleyAddress baseScriptStakeAddress({required BcAbstractScript script});
  ShelleyAddress baseKeyScriptAddress(
      {required BcAbstractScript script, int index = 0});
  ShelleyAddress pointerAddress({required BcPointer pointer, int index = 0});
  ShelleyAddress enterpriseAddress({int index = 0});
  ShelleyAddress get stakeAddress;
  List<ShelleyReceiveKit> unusedReceiveAddresses({
    Segment role = spendRole,
    int startIndex = 0,
    int beyondUsedOffset = defaultBeyondUsedOffset,
    UsedAddressFunction usedCallback = alwaysUsed,
    bool includeUsed = false,
  });
}

///
/// Read-only Audit Account using public keys.
///
class HdAudit implements HdAddressGenerator, HdLegacyReceiver {
  @override
  final HdUseCase useCase = HdUseCase.audits;
  @override
  final Networks network;
  final ShelleyKeyDerivation derivation;
  final ShelleyKeyDerivation derivationInternal;
  final DerivationChain chain;
  late final Bip32VerifyKey publicStakeKey;
  final int accountIndex;

  HdAudit({
    required Bip32VerifyKey publicExternalKey,
    required Bip32VerifyKey publicInternalKey,
    required this.publicStakeKey,
    this.network = Networks.mainnet,
    this.accountIndex = 0,
  })  : chain = const DerivationChain(key: 'M', segments: []),
        derivation = ShelleyKeyDerivation(publicExternalKey),
        derivationInternal = ShelleyKeyDerivation(publicInternalKey);

  Bip32VerifyKey externalAddrPublicKey({int index = 0}) =>
      derivation.fromChain(chain.append(Segment(index: index)))
          as Bip32VerifyKey;

  Bip32VerifyKey internalAddrPublicKey({int index = 0}) =>
      derivationInternal.fromChain(chain.append(Segment(index: index)))
          as Bip32VerifyKey;

  @override
  ShelleyAddress baseAddress({int index = 0}) => ShelleyAddress.baseAddress(
      spend: externalAddrPublicKey(index: index),
      stake: publicStakeKey,
      network: network);

  @override
  ShelleyAddress changeAddress({int index = 0}) => ShelleyAddress.baseAddress(
      spend: internalAddrPublicKey(index: index),
      stake: publicStakeKey,
      network: network);

  @override
  ShelleyAddress get stakeAddress =>
      ShelleyAddress.rewardAddress(stakeKey: publicStakeKey, network: network);

  @override
  ShelleyAddress baseKeyScriptAddress(
          {required BcAbstractScript script, int index = 0}) =>
      ShelleyAddress.baseKeyScriptAddress(
          spend: externalAddrPublicKey(index: index),
          script: script,
          network: network);

  @override
  ShelleyAddress baseScriptStakeAddress({required BcAbstractScript script}) =>
      ShelleyAddress.baseScriptStakeAddress(
          script: script, stake: publicStakeKey, network: network);
  @override
  ShelleyAddress enterpriseAddress({int index = 0}) =>
      ShelleyAddress.enterpriseAddress(
          spend: externalAddrPublicKey(index: index), network: network);

  @override
  ShelleyAddress pointerAddress({required BcPointer pointer, int index = 0}) =>
      ShelleyAddress.pointerAddress(
          pointer: pointer,
          verifyKey: externalAddrPublicKey(index: index),
          network: network);

  @override
  List<ShelleyReceiveKit> unusedReceiveAddresses({
    Segment role = spendRole,
    int startIndex = 0,
    int beyondUsedOffset = defaultBeyondUsedOffset,
    UsedAddressFunction usedCallback = alwaysUsed,
    bool includeUsed = false,
  }) =>
      _unusedReceiveAddresses(
        generator: this,
        network: network,
        accountIndex: accountIndex,
        role: role,
        startIndex: startIndex,
        beyondUsedOffset: beyondUsedOffset,
        usedCallback: usedCallback,
        includeUsed: includeUsed,
      );

  @override
  AbstractAddress receiveAddress({int index = 0}) => baseAddress(index: index);

  String get chainLabel => "M/$accountIndex'";
}

///
/// Generates addresses.
///
abstract class HdAddressSigner extends HdAddressGenerator {
  Bip32SigningKey basePrivateKey({int index = 0});
  Bip32SigningKey changePrivateKey({int index = 0});
  Bip32SigningKey get stakePrivateKey;
  List<ShelleyUtxoKit> signableAddresses({
    required Set<ShelleyAddress> utxos,
    int startIndex = 0,
  });
}

/// Office Account
class HdAccount implements HdAddressSigner, HdLegacyReceiver {
  @override
  final HdUseCase useCase = HdUseCase.perOfficeBalances;
  final ShelleyKeyDerivation derivation;
  @override
  final Networks network;
  final int accountIndex;
  final Bip32SigningKey
      accountSigningKey; //Pvt key at account level m/1852'/1815'/x'
  final DerivationChain chain;
  late final Bip32VerifyKey publicStakeKey;

  HdAccount({
    required this.accountSigningKey,
    this.network = Networks.mainnet,
    this.accountIndex = 0,
  })  : chain = const DerivationChain(key: 'm', segments: []),
        // chainKey = DerivationChain(key: 'm', segments: [
        //   cip1852,
        //   cip1815,
        //   Segment(index: accountIndex, harden: true)
        // ]),
        derivation = ShelleyKeyDerivation(accountSigningKey) {
    publicStakeKey = derivation
        .fromChain(chain.append2(stakeRole, zeroSoft))
        .publicKey as Bip32VerifyKey;
  }

  HdAudit get audit => HdAudit(
        publicExternalKey: basePrivateKey().publicKey,
        publicInternalKey: changePrivateKey().publicKey,
        publicStakeKey: stakePrivateKey.publicKey,
        network: network,
        accountIndex: accountIndex,
      );

  @override
  Bip32SigningKey basePrivateKey({int index = 0}) =>
      derivation.fromChain(chain.append2(spendRole, Segment(index: index)))
          as Bip32SigningKey;

  @override
  Bip32SigningKey changePrivateKey({int index = 0}) =>
      derivation.fromChain(chain.append2(changeRole, Segment(index: index)))
          as Bip32SigningKey;

  @override
  Bip32SigningKey get stakePrivateKey =>
      derivation.fromChain(chain.append2(stakeRole, zeroSoft))
          as Bip32SigningKey;

  @override
  ShelleyAddress baseAddress({int index = 0}) => ShelleyAddress.baseAddress(
      spend: basePrivateKey(index: index).verifyKey,
      stake: publicStakeKey,
      network: network);

  @override
  ShelleyAddress changeAddress({int index = 0}) => ShelleyAddress.baseAddress(
      spend: changePrivateKey(index: index).verifyKey,
      stake: publicStakeKey,
      network: network);

  @override
  ShelleyAddress get stakeAddress =>
      ShelleyAddress.rewardAddress(stakeKey: publicStakeKey, network: network);

  @override
  ShelleyAddress baseKeyScriptAddress(
          {required BcAbstractScript script, int index = 0}) =>
      ShelleyAddress.baseKeyScriptAddress(
          spend: basePrivateKey(index: index).verifyKey,
          script: script,
          network: network);

  @override
  ShelleyAddress pointerAddress({required BcPointer pointer, int index = 0}) =>
      ShelleyAddress.pointerAddress(
          verifyKey: basePrivateKey(index: index).verifyKey,
          pointer: pointer,
          network: network);

  ShelleyAddress enterpriseScriptAddress({required BcAbstractScript script}) =>
      ShelleyAddress.enterpriseScriptAddress(script: script, network: network);

  @override
  ShelleyAddress baseScriptStakeAddress({required BcAbstractScript script}) =>
      ShelleyAddress.baseScriptStakeAddress(
          script: script, stake: publicStakeKey, network: network);

  @override
  ShelleyAddress enterpriseAddress({int index = 0}) =>
      ShelleyAddress.enterpriseAddress(
          spend: basePrivateKey(index: index).verifyKey, network: network);

  @override
  List<ShelleyReceiveKit> unusedReceiveAddresses({
    Segment role = spendRole,
    int startIndex = 0,
    int beyondUsedOffset = defaultBeyondUsedOffset,
    UsedAddressFunction usedCallback = alwaysUsed,
    bool includeUsed = false,
  }) =>
      _unusedReceiveAddresses(
        generator: this,
        network: network,
        accountIndex: accountIndex,
        role: role,
        startIndex: startIndex,
        beyondUsedOffset: beyondUsedOffset,
        usedCallback: usedCallback,
        includeUsed: includeUsed,
      );

  @override
  List<ShelleyUtxoKit> signableAddresses({
    required Set<ShelleyAddress> utxos,
    int startIndex = 0,
  }) =>
      _signableAddresses(
        utxos: utxos,
        generator: this,
        network: network,
        accountIndex: accountIndex,
        startIndex: startIndex,
      );

  @override
  AbstractAddress receiveAddress({int index = 0}) => baseAddress(index: index);

  String get chainLabel => "m/1852'/1815'/$accountIndex'";
}

///
/// The HD master contains the master private key allowing it create any type of Account.
///
/// 99% of the time you'll just create a master using a mnemonic and get the
/// default account:
///
///   HdAccount account = HdMaster.mnemonic(['head', 'guard',...]).account();
///
/// Unless specified, the default network is mainnet.
///
class HdMaster implements HdAbstract {
  @override
  final HdUseCase useCase = HdUseCase.fullWalletSharing;
  @override
  final Networks network;
  final DerivationChain chain = const DerivationChain(key: 'm', segments: [
    cip1852,
    cip1815,
  ]);
  final ShelleyKeyDerivation derivation;
  String get chainLabel => 'm';

  HdMaster({
    required this.derivation,
    this.network = Networks.mainnet,
  });

  HdMaster.entropy(Uint8List entropy, {Networks network = Networks.mainnet})
      : this(
            network: network,
            derivation: ShelleyKeyDerivation.entropy(entropy));

  HdMaster.entropyHex(String entropyHex, {Networks network = Networks.mainnet})
      : this(
            network: network,
            derivation: ShelleyKeyDerivation.entropyHex(entropyHex));

  // ignore: non_constant_identifier_names
  HdMaster.bech32(String root_sk, {Networks network = Networks.mainnet})
      : this(network: network, derivation: ShelleyKeyDerivation.rootX(root_sk));

  HdMaster.mnemonic(
    ValidMnemonicPhrase mnemonic, {
    LoadMnemonicWordsFunction loadWordsFunction = loadEnglishMnemonicWords,
    MnemonicLang lang = MnemonicLang.english,
    Networks network = Networks.mainnet,
  }) : this.entropyHex(
            mnemonicToEntropyHex(
                mnemonic: mnemonic,
                loadWordsFunction: loadWordsFunction,
                lang: lang),
            network: network);

  Bip32SigningKey get masterPrivateKey => derivation.root as Bip32SigningKey;

  /// Lookup and/or create an account if one doesn't exist.
  /// The default zero index will be used if not specified.
  /// Paths are generated using the "m/1852'/1815'/$index'" template.
  HdAccount account({int accountIndex = 0}) =>
      accountByPath(_acctPathTemplate(accountIndex));

  /// Look up an account based on it's path. Paths define the cryptocraphic key of the account
  /// from which all other account keys and addresses are derived.
  HdAccount accountByPath(String path) {
    final derivationPath = DerivationChain.fromPath(path);
    final accountKey = derivation.fromChain(derivationPath) as Bip32SigningKey;
    return HdAccount(
        accountSigningKey: accountKey,
        accountIndex: derivationPath.segments.last.index,
        network: network);
  }

  ///
  /// Audit for specific account index that can generate all internal (change) and external (spend) addresses.
  ///
  HdAudit audit({int accountIndex = 0}) {
    final chain = DerivationChain.fromPath(_acctPathTemplate(accountIndex));
    final ext = derivation.fromChain(chain.append(spendRole)).publicKey;
    final int = derivation.fromChain(chain.append(changeRole)).publicKey;
    final stake =
        derivation.fromChain(chain.append2(stakeRole, zeroSoft)).publicKey;
    return HdAudit(
      publicExternalKey: ext as Bip32VerifyKey,
      publicInternalKey: int as Bip32VerifyKey,
      publicStakeKey: stake as Bip32VerifyKey,
      network: network,
      accountIndex: accountIndex,
    );
  }

  // static const _defaultAcctPath = "m/1852'/1815'/0'";
  String _acctPathTemplate(int accountIndex) => "m/1852'/1815'/$accountIndex'";
}

class InvalidAccountError extends Error {
  final String message;
  InvalidAccountError(this.message);
  @override
  String toString() => message;
}

/// Encapsulates a ShelleyAddress, it's BIP32 path and if it's
/// been used in a existing transaction.
class ShelleyReceiveKit {
  final ShelleyAddress address;
  final DerivationChain chain;
  final bool used;
  const ShelleyReceiveKit({
    required this.address,
    required this.chain,
    required this.used,
  });
}

/// Encapsulates a ShelleyAddress, it's BIP32 path add it's a
/// signing key so it can be spent in a UTxO transaction.
class ShelleyUtxoKit {
  final ShelleyAddress address;
  final DerivationChain chain;
  final Bip32SigningKey signingKey;
  const ShelleyUtxoKit({
    required this.address,
    required this.chain,
    required this.signingKey,
  });
}

const defaultBeyondUsedOffset = 10;

/// Iterate address tree collecting unused addresses until beyondUsedOffset are found.
/// If usedSet is empty, all addresses are treated as unused.
List<ShelleyReceiveKit> _unusedReceiveAddresses({
  required HdAddressGenerator generator,
  UsedAddressFunction usedCallback = alwaysUsed,
  int beyondUsedOffset = defaultBeyondUsedOffset,
  required Networks network,
  int accountIndex = 0,
  Segment role = spendRole,
  int startIndex = 0,
  bool includeUsed = false,
}) {
  assert(beyondUsedOffset > 0);
  assert(accountIndex >= 0);
  assert(role == spendRole || role == changeRole);
  assert(startIndex >= 0);
  // "m/1852'/1815'/$accountIndex'/$role/$addrIndex"
  final baseChain = DerivationChain(key: 'm', segments: [
    cip1852,
    cip1815,
    Segment(index: accountIndex, harden: true),
    role
  ]);
  List<ShelleyReceiveKit> results = [];
  int cutoff = beyondUsedOffset;
  var index = startIndex;
  do {
    var address = role == spendRole
        ? generator.baseAddress(index: index)
        : generator.changeAddress(index: index);
    final isUsed = usedCallback.call(address);
    if (includeUsed || !isUsed) {
      results.add(ShelleyReceiveKit(
        address: address,
        chain: baseChain.append(Segment(index: index)),
        used: isUsed,
      ));
    }
    if (isUsed) {
      cutoff = beyondUsedOffset + index + 1; //extend cache size
    }
  } while (++index < cutoff && index < 31 ^ 2);
  return results;
}

// iterate address tree until addressCount unused addresses are found.
// List<ShelleyReceiveKit> _unusedReceiveAddressesOld({
//   required HdAddressGenerator generator,
//   required Networks network,
//   int accountIndex = 0,
//   Segment role = spendRole,
//   int startIndex = 0,
//   int addressCount = 1,
//   required UnusedAddressFunction unusedCallback,
//   bool includeUsed = false,
// }) {
//   assert(accountIndex >= 0);
//   assert(role == spendRole || role == changeRole);
//   assert(startIndex >= 0);
//   assert(addressCount >= 1);
//   // "m/1852'/1815'/$accountIndex'/$role/$addrIndex"
//   final baseChain = DerivationChain(key: 'm', segments: [
//     cip1852,
//     cip1815,
//     Segment(index: accountIndex, harden: true),
//     role
//   ]);
//   List<ShelleyReceiveKit> results = [];
//   for (int index = startIndex; index < 31 ^ 2; index++) {
//     var address = role == spendRole
//         ? generator.baseAddress(index: index)
//         : generator.changeAddress(index: index);
//     if (includeUsed || unusedCallback.call(address)) {
//       results.add(ShelleyReceiveKit(
//         address: address,
//         chain: baseChain.append(Segment(index: index)),
//         used: !unusedCallback.call(address),
//       ));
//     }
//     if (results.length == addressCount) break;
//   }
//   return results;
// }

/// Match addresses to their private keys so they can be signed/spent.
/// Searches both internal and external chains.
List<ShelleyUtxoKit> _signableAddresses({
  required Set<ShelleyAddress> utxos,
  required HdAddressSigner generator,
  required Networks network,
  int accountIndex = 0,
  int startIndex = 0,
}) {
  assert(accountIndex >= 0);
  assert(startIndex >= 0);
  // "m/1852'/1815'/$accountIndex'"
  final acctChain = DerivationChain(key: 'm', segments: [
    cip1852,
    cip1815,
    Segment(index: accountIndex, harden: true),
  ]);
  List<ShelleyUtxoKit> results = [];
  for (int index = startIndex; index < 31 ^ 2; index++) {
    for (Segment role in [spendRole, changeRole]) {
      final address = role == spendRole
          ? generator.baseAddress(index: index)
          : generator.changeAddress(index: index);
      if (utxos.contains(address)) {
        results.add(ShelleyUtxoKit(
          address: address,
          chain: acctChain.append2(role, Segment(index: index)),
          signingKey: generator.basePrivateKey(index: index),
        ));
      }
      if (results.length == utxos.length) break;
    }
  }
  return results;
}
