import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

/// Supported app languages. Add a new entry plus its column in [_strings] to
/// extend — nothing else needs to change.
enum AppLanguage {
  english('en', 'English'),
  hindi('hi', 'हिन्दी'),
  telugu('te', 'తెలుగు');

  const AppLanguage(this.code, this.nativeName);
  final String code;
  final String nativeName;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) => AppLanguage.values
      .firstWhere((e) => e.code == code, orElse: () => AppLanguage.english);
}

/// Tiny map-backed localization. English is the source of truth and the
/// fallback for any missing key or language.
class AppLocalizations {
  const AppLocalizations(this.locale);
  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('en'));

  static const delegate = _AppLocalizationsDelegate();
  static const supportedLocales = [Locale('en'), Locale('hi'), Locale('te')];

  String t(String key) {
    final lang = _strings[locale.languageCode] ?? _strings['en']!;
    return lang[key] ?? _strings['en']![key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => _strings.containsKey(locale.languageCode);
  @override
  // Synchronous so the first frame already has strings (no blank flash, and
  // widget tests don't need an extra pump).
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

const Map<String, Map<String, String>> _strings = {
  'en': {
    // Navigation
    'nav.home': 'Home',
    'nav.dashboard': 'Dashboard',
    'nav.manage': 'Manage',
    'nav.rent': 'Rent',
    'nav.myRent': 'My Rent',
    'nav.requests': 'Requests',
    'nav.myRequests': 'My Requests',
    'nav.visitors': 'Visitors',
    'nav.profile': 'Profile',
    'nav.properties': 'Properties',
    'nav.operations': 'Operations',
    // Common
    'common.save': 'Save',
    'common.cancel': 'Cancel',
    'common.update': 'Update',
    'common.close': 'Close',
    'common.signOut': 'Sign out',
    'common.edit': 'Edit',
    // Profile
    'profile.personal': 'Personal details',
    'profile.personalSub': 'Name, phone, email',
    'profile.kyc': 'KYC & documents',
    'profile.changePassword': 'Change password',
    'profile.changePasswordSub': 'Update your account password',
    'profile.settings': 'App settings',
    'profile.settingsSub': 'Language, notifications, account',
    'profile.help': 'Help & support',
    'profile.helpSub': 'FAQs and contact support',
    'profile.businessDetails': 'Business details',
    // Settings
    'settings.title': 'Settings',
    'settings.language': 'Language',
    'settings.languageSub': 'Choose your preferred language',
    'settings.notifications': 'Notifications',
    'settings.push': 'Push notifications',
    'settings.pushSub': 'Get alerts on this device',
    'settings.account': 'Account',
    'settings.appInfo': 'About',
    'settings.version': 'Version',
    'settings.saved': 'Settings saved',
    'settings.languageChanged': 'Language updated',
    // Help
    'help.title': 'Help & support',
    'help.intro':
        'We\'re here to help. Reach us and we\'ll respond within a day.',
    'help.email': 'Email support',
    'help.call': 'Call support',
    'help.faqTitle': 'Frequently asked',
    // Announcements
    'ann.title': 'Announcements',
    'ann.communitySub': 'Important notices from your PG.',
    'ann.new': 'New announcement',
    'ann.broadcast': 'Broadcast',
    'ann.titleLabel': 'Title',
    'ann.messageLabel': 'Message',
    'ann.audience': 'Audience',
    'ann.audienceAll': 'All tenants',
    'ann.sendPush': 'Send push notification',
    'ann.sendPushSub': 'Notify tenants immediately',
    'ann.publish': 'Publish announcement',
    'ann.published': 'Announcement published',
    'ann.postedBy': 'Posted by',
    'ann.empty': 'No announcements yet',
    'ann.validation': 'Enter a title and a message.',
    // Empty states
    'empty.nothingNew': 'Nothing new yet',
    'empty.noNotifications': 'No notifications yet',
  },
  'hi': {
    'nav.home': 'होम',
    'nav.dashboard': 'डैशबोर्ड',
    'nav.manage': 'प्रबंधन',
    'nav.rent': 'किराया',
    'nav.myRent': 'मेरा किराया',
    'nav.requests': 'अनुरोध',
    'nav.myRequests': 'मेरे अनुरोध',
    'nav.visitors': 'आगंतुक',
    'nav.profile': 'प्रोफ़ाइल',
    'nav.properties': 'संपत्तियाँ',
    'nav.operations': 'संचालन',
    'common.save': 'सहेजें',
    'common.cancel': 'रद्द करें',
    'common.update': 'अपडेट करें',
    'common.close': 'बंद करें',
    'common.signOut': 'साइन आउट',
    'common.edit': 'संपादित करें',
    'profile.personal': 'व्यक्तिगत विवरण',
    'profile.personalSub': 'नाम, फ़ोन, ईमेल',
    'profile.kyc': 'केवाईसी और दस्तावेज़',
    'profile.changePassword': 'पासवर्ड बदलें',
    'profile.changePasswordSub': 'अपना खाता पासवर्ड अपडेट करें',
    'profile.settings': 'ऐप सेटिंग्स',
    'profile.settingsSub': 'भाषा, सूचनाएँ, खाता',
    'profile.help': 'सहायता और समर्थन',
    'profile.helpSub': 'सामान्य प्रश्न और संपर्क',
    'profile.businessDetails': 'व्यवसाय विवरण',
    'settings.title': 'सेटिंग्स',
    'settings.language': 'भाषा',
    'settings.languageSub': 'अपनी पसंदीदा भाषा चुनें',
    'settings.notifications': 'सूचनाएँ',
    'settings.push': 'पुश सूचनाएँ',
    'settings.pushSub': 'इस डिवाइस पर अलर्ट पाएँ',
    'settings.account': 'खाता',
    'settings.appInfo': 'परिचय',
    'settings.version': 'संस्करण',
    'settings.saved': 'सेटिंग्स सहेजी गईं',
    'settings.languageChanged': 'भाषा अपडेट हुई',
    'help.title': 'सहायता और समर्थन',
    'help.intro':
        'हम मदद के लिए यहाँ हैं। हमसे संपर्क करें, हम एक दिन में जवाब देंगे।',
    'help.email': 'ईमेल समर्थन',
    'help.call': 'कॉल समर्थन',
    'help.faqTitle': 'अक्सर पूछे जाने वाले प्रश्न',
    'ann.title': 'घोषणाएँ',
    'ann.communitySub': 'आपके पीजी से महत्वपूर्ण सूचनाएँ।',
    'ann.new': 'नई घोषणा',
    'ann.broadcast': 'प्रसारण',
    'ann.titleLabel': 'शीर्षक',
    'ann.messageLabel': 'संदेश',
    'ann.audience': 'दर्शक',
    'ann.audienceAll': 'सभी किरायेदार',
    'ann.sendPush': 'पुश सूचना भेजें',
    'ann.sendPushSub': 'किरायेदारों को तुरंत सूचित करें',
    'ann.publish': 'घोषणा प्रकाशित करें',
    'ann.published': 'घोषणा प्रकाशित हुई',
    'ann.postedBy': 'द्वारा पोस्ट किया गया',
    'ann.empty': 'अभी कोई घोषणा नहीं',
    'ann.validation': 'शीर्षक और संदेश दर्ज करें।',
    'empty.nothingNew': 'अभी कुछ नया नहीं',
    'empty.noNotifications': 'अभी कोई सूचना नहीं',
  },
  'te': {
    'nav.home': 'హోమ్',
    'nav.dashboard': 'డాష్‌బోర్డ్',
    'nav.manage': 'నిర్వహణ',
    'nav.rent': 'అద్దె',
    'nav.myRent': 'నా అద్దె',
    'nav.requests': 'అభ్యర్థనలు',
    'nav.myRequests': 'నా అభ్యర్థనలు',
    'nav.visitors': 'సందర్శకులు',
    'nav.profile': 'ప్రొఫైల్',
    'nav.properties': 'ఆస్తులు',
    'nav.operations': 'నిర్వహణలు',
    'common.save': 'సేవ్ చేయి',
    'common.cancel': 'రద్దు చేయి',
    'common.update': 'నవీకరించు',
    'common.close': 'మూసివేయి',
    'common.signOut': 'సైన్ అవుట్',
    'common.edit': 'సవరించు',
    'profile.personal': 'వ్యక్తిగత వివరాలు',
    'profile.personalSub': 'పేరు, ఫోన్, ఇమెయిల్',
    'profile.kyc': 'కేవైసీ & పత్రాలు',
    'profile.changePassword': 'పాస్‌వర్డ్ మార్చు',
    'profile.changePasswordSub': 'మీ ఖాతా పాస్‌వర్డ్‌ను నవీకరించండి',
    'profile.settings': 'యాప్ సెట్టింగ్‌లు',
    'profile.settingsSub': 'భాష, నోటిఫికేషన్‌లు, ఖాతా',
    'profile.help': 'సహాయం & మద్దతు',
    'profile.helpSub': 'తరచు ప్రశ్నలు మరియు సంప్రదింపు',
    'profile.businessDetails': 'వ్యాపార వివరాలు',
    'settings.title': 'సెట్టింగ్‌లు',
    'settings.language': 'భాష',
    'settings.languageSub': 'మీకు నచ్చిన భాషను ఎంచుకోండి',
    'settings.notifications': 'నోటిఫికేషన్‌లు',
    'settings.push': 'పుష్ నోటిఫికేషన్‌లు',
    'settings.pushSub': 'ఈ పరికరంలో హెచ్చరికలు పొందండి',
    'settings.account': 'ఖాతా',
    'settings.appInfo': 'గురించి',
    'settings.version': 'వెర్షన్',
    'settings.saved': 'సెట్టింగ్‌లు సేవ్ అయ్యాయి',
    'settings.languageChanged': 'భాష నవీకరించబడింది',
    'help.title': 'సహాయం & మద్దతు',
    'help.intro':
        'మేము సహాయం చేయడానికి ఇక్కడ ఉన్నాము. మమ్మల్ని సంప్రదించండి, ఒక రోజులో స్పందిస్తాము.',
    'help.email': 'ఇమెయిల్ మద్దతు',
    'help.call': 'కాల్ మద్దతు',
    'help.faqTitle': 'తరచు అడిగే ప్రశ్నలు',
    'ann.title': 'ప్రకటనలు',
    'ann.communitySub': 'మీ పీజీ నుండి ముఖ్యమైన నోటీసులు.',
    'ann.new': 'కొత్త ప్రకటన',
    'ann.broadcast': 'ప్రసారం',
    'ann.titleLabel': 'శీర్షిక',
    'ann.messageLabel': 'సందేశం',
    'ann.audience': 'ప్రేక్షకులు',
    'ann.audienceAll': 'అందరు అద్దెదారులు',
    'ann.sendPush': 'పుష్ నోటిఫికేషన్ పంపు',
    'ann.sendPushSub': 'అద్దెదారులకు వెంటనే తెలియజేయి',
    'ann.publish': 'ప్రకటన ప్రచురించు',
    'ann.published': 'ప్రకటన ప్రచురించబడింది',
    'ann.postedBy': 'పోస్ట్ చేసినవారు',
    'ann.empty': 'ఇంకా ప్రకటనలు లేవు',
    'ann.validation': 'శీర్షిక మరియు సందేశాన్ని నమోదు చేయండి.',
    'empty.nothingNew': 'ఇంకా కొత్తది ఏమీ లేదు',
    'empty.noNotifications': 'ఇంకా నోటిఫికేషన్‌లు లేవు',
  },
};
