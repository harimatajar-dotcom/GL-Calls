class CountryCode {
  final String name;
  final String code;
  final String dialCode;
  final String flag;

  const CountryCode({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
  });
}

class CountryCodes {
  CountryCodes._();

  static const List<CountryCode> all = [
    CountryCode(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳'),
    CountryCode(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸'),
    CountryCode(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧'),
    CountryCode(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦'),
    CountryCode(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺'),
    CountryCode(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪'),
    CountryCode(name: 'France', code: 'FR', dialCode: '+33', flag: '🇫🇷'),
    CountryCode(name: 'Italy', code: 'IT', dialCode: '+39', flag: '🇮🇹'),
    CountryCode(name: 'Spain', code: 'ES', dialCode: '+34', flag: '🇪🇸'),
    CountryCode(name: 'Brazil', code: 'BR', dialCode: '+55', flag: '🇧🇷'),
    CountryCode(name: 'Mexico', code: 'MX', dialCode: '+52', flag: '🇲🇽'),
    CountryCode(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵'),
    CountryCode(name: 'China', code: 'CN', dialCode: '+86', flag: '🇨🇳'),
    CountryCode(name: 'South Korea', code: 'KR', dialCode: '+82', flag: '🇰🇷'),
    CountryCode(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬'),
    CountryCode(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾'),
    CountryCode(name: 'Indonesia', code: 'ID', dialCode: '+62', flag: '🇮🇩'),
    CountryCode(name: 'Thailand', code: 'TH', dialCode: '+66', flag: '🇹🇭'),
    CountryCode(name: 'Vietnam', code: 'VN', dialCode: '+84', flag: '🇻🇳'),
    CountryCode(name: 'Philippines', code: 'PH', dialCode: '+63', flag: '🇵🇭'),
    CountryCode(name: 'United Arab Emirates', code: 'AE', dialCode: '+971', flag: '🇦🇪'),
    CountryCode(name: 'Saudi Arabia', code: 'SA', dialCode: '+966', flag: '🇸🇦'),
    CountryCode(name: 'South Africa', code: 'ZA', dialCode: '+27', flag: '🇿🇦'),
    CountryCode(name: 'Nigeria', code: 'NG', dialCode: '+234', flag: '🇳🇬'),
    CountryCode(name: 'Kenya', code: 'KE', dialCode: '+254', flag: '🇰🇪'),
    CountryCode(name: 'Egypt', code: 'EG', dialCode: '+20', flag: '🇪🇬'),
    CountryCode(name: 'Pakistan', code: 'PK', dialCode: '+92', flag: '🇵🇰'),
    CountryCode(name: 'Bangladesh', code: 'BD', dialCode: '+880', flag: '🇧🇩'),
    CountryCode(name: 'Sri Lanka', code: 'LK', dialCode: '+94', flag: '🇱🇰'),
    CountryCode(name: 'Nepal', code: 'NP', dialCode: '+977', flag: '🇳🇵'),
  ];

  static CountryCode get defaultCountry => all.first;
}
