class CountryCode {
  final String name;
  final String code;
  final String dialCode;
  final String flag;
  final int phoneLength; // Required digits for phone number (after country code)

  const CountryCode({
    required this.name,
    required this.code,
    required this.dialCode,
    required this.flag,
    this.phoneLength = 10,
  });
}

class CountryCodes {
  CountryCodes._();

  static const List<CountryCode> all = [
    CountryCode(name: 'India', code: 'IN', dialCode: '+91', flag: '🇮🇳', phoneLength: 10),
    CountryCode(name: 'United States', code: 'US', dialCode: '+1', flag: '🇺🇸', phoneLength: 10),
    CountryCode(name: 'United Kingdom', code: 'GB', dialCode: '+44', flag: '🇬🇧', phoneLength: 10),
    CountryCode(name: 'Canada', code: 'CA', dialCode: '+1', flag: '🇨🇦', phoneLength: 10),
    CountryCode(name: 'Australia', code: 'AU', dialCode: '+61', flag: '🇦🇺', phoneLength: 9),
    CountryCode(name: 'Germany', code: 'DE', dialCode: '+49', flag: '🇩🇪', phoneLength: 11),
    CountryCode(name: 'France', code: 'FR', dialCode: '+33', flag: '🇫🇷', phoneLength: 9),
    CountryCode(name: 'Italy', code: 'IT', dialCode: '+39', flag: '🇮🇹', phoneLength: 10),
    CountryCode(name: 'Spain', code: 'ES', dialCode: '+34', flag: '🇪🇸', phoneLength: 9),
    CountryCode(name: 'Brazil', code: 'BR', dialCode: '+55', flag: '🇧🇷', phoneLength: 11),
    CountryCode(name: 'Mexico', code: 'MX', dialCode: '+52', flag: '🇲🇽', phoneLength: 10),
    CountryCode(name: 'Japan', code: 'JP', dialCode: '+81', flag: '🇯🇵', phoneLength: 10),
    CountryCode(name: 'China', code: 'CN', dialCode: '+86', flag: '🇨🇳', phoneLength: 11),
    CountryCode(name: 'South Korea', code: 'KR', dialCode: '+82', flag: '🇰🇷', phoneLength: 10),
    CountryCode(name: 'Singapore', code: 'SG', dialCode: '+65', flag: '🇸🇬', phoneLength: 8),
    CountryCode(name: 'Malaysia', code: 'MY', dialCode: '+60', flag: '🇲🇾', phoneLength: 10),
    CountryCode(name: 'Indonesia', code: 'ID', dialCode: '+62', flag: '🇮🇩', phoneLength: 11),
    CountryCode(name: 'Thailand', code: 'TH', dialCode: '+66', flag: '🇹🇭', phoneLength: 9),
    CountryCode(name: 'Vietnam', code: 'VN', dialCode: '+84', flag: '🇻🇳', phoneLength: 9),
    CountryCode(name: 'Philippines', code: 'PH', dialCode: '+63', flag: '🇵🇭', phoneLength: 10),
    CountryCode(name: 'United Arab Emirates', code: 'AE', dialCode: '+971', flag: '🇦🇪', phoneLength: 9),
    CountryCode(name: 'Saudi Arabia', code: 'SA', dialCode: '+966', flag: '🇸🇦', phoneLength: 9),
    CountryCode(name: 'South Africa', code: 'ZA', dialCode: '+27', flag: '🇿🇦', phoneLength: 9),
    CountryCode(name: 'Nigeria', code: 'NG', dialCode: '+234', flag: '🇳🇬', phoneLength: 10),
    CountryCode(name: 'Kenya', code: 'KE', dialCode: '+254', flag: '🇰🇪', phoneLength: 9),
    CountryCode(name: 'Egypt', code: 'EG', dialCode: '+20', flag: '🇪🇬', phoneLength: 10),
    CountryCode(name: 'Pakistan', code: 'PK', dialCode: '+92', flag: '🇵🇰', phoneLength: 10),
    CountryCode(name: 'Bangladesh', code: 'BD', dialCode: '+880', flag: '🇧🇩', phoneLength: 10),
    CountryCode(name: 'Sri Lanka', code: 'LK', dialCode: '+94', flag: '🇱🇰', phoneLength: 9),
    CountryCode(name: 'Nepal', code: 'NP', dialCode: '+977', flag: '🇳🇵', phoneLength: 10),
  ];

  static CountryCode get defaultCountry => all.first;
}
