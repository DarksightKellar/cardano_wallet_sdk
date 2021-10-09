import 'package:cardano_wallet_sdk/src/address/shelley_address.dart';
import 'package:cardano_wallet_sdk/src/asset/asset.dart';
import 'package:cardano_wallet_sdk/src/network/cardano_network.dart';
import 'package:cardano_wallet_sdk/src/stake/stake_account.dart';
import 'package:cardano_wallet_sdk/src/transaction/transaction.dart';

enum TransactionQueryType { all, used, unused }

///
/// public Cardano wallet holding stakingAddress and associated public tranaction addresses.
///
abstract class ReadOnlyWallet {
  /// networkId is either mainnet or nestnet
  NetworkId get networkId;

  /// name of wallet
  String get walletName;

  /// balance of wallet in lovelace
  int get balance;

  /// calculate balance from transactions and rewards
  int get calculatedBalance;

  /// balances of native tokens indexed by assetId
  Map<String, int> get currencies;

  /// optional stake pool details
  List<StakeAccount> get stakeAccounts;

  /// assets present in this wallet indexed by assetId
  Map<String, CurrencyAsset> get assets;
  List<WalletTransaction> get transactions;
  List<WalletTransaction> filterTransactions({required String assetId});
  List<ShelleyAddress> addresses({TransactionQueryType type = TransactionQueryType.all});
  bool refresh(
      {required int balance,
      required List<Transaction> transactions,
      required List<ShelleyAddress> usedAddresses,
      required Map<String, CurrencyAsset> assets,
      required List<StakeAccount> stakeAccounts});

  CurrencyAsset? findAssetWhere(bool Function(CurrencyAsset asset) matcher);
  CurrencyAsset? findAssetByTicker(String ticker);
}