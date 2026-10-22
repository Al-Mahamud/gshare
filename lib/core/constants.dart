const String kAppName = 'gshare';
const int kProtocolVersion = 1;

const int kDefaultPort = 47820;
const String kMulticastGroup = '239.255.77.77';
const int kMulticastPort = 47821;
const String kMdnsType = '_gshare._tcp';
const String kApiBase = '/api/v1';

const Duration kAcceptTimeout = Duration(seconds: 60);
const Duration kReceiveIdleTimeout = Duration(minutes: 3);
const int kMaxItemsPerSession = 5000;
