export type AppLanguageOption = {
  code: string;
  label: string;
};

export const APP_LANGUAGE_STORAGE_KEY = "openpay_app_language";

const normalizeLanguageTag = (value: string) => {
  const raw = String(value || "").trim().replace(/_/g, "-");
  if (!raw) return "en";

  const [baseRaw, regionRaw] = raw.split("-", 2);
  const base = baseRaw.toLowerCase();
  if (!regionRaw) return base;

  const region = regionRaw.length === 2 ? regionRaw.toUpperCase() : regionRaw;
  return `${base}-${region}`;
};

const toGoogleTranslateCode = (languageCode: string) => {
  const tag = normalizeLanguageTag(languageCode);
  const [base, region] = tag.split("-", 2);

  // Google Translate cookie language codes (TranslateElement) use some legacy/alias tags.
  const aliasBase =
    base === "he"
      ? "iw"
      : base === "jv"
        ? "jw"
        : base === "yi"
          ? "ji"
          : base === "fil"
            ? "tl"
            : base === "nb" || base === "nn"
              ? "no"
              : base;

  return region ? `${aliasBase}-${region}` : aliasBase;
};

export const APP_LANGUAGE_OPTIONS: AppLanguageOption[] = [
  { code: "af", label: "Afrikaans" },
  { code: "sq", label: "Albanian" },
  { code: "am", label: "Amharic" },
  { code: "ar", label: "Arabic" },
  { code: "hy", label: "Armenian" },
  { code: "as", label: "Assamese" },
  { code: "az", label: "Azerbaijani" },
  { code: "eu", label: "Basque" },
  { code: "be", label: "Belarusian" },
  { code: "bn", label: "Bengali" },
  { code: "bs", label: "Bosnian" },
  { code: "bg", label: "Bulgarian" },
  { code: "ca", label: "Catalan" },
  { code: "ceb", label: "Cebuano" },
  { code: "ny", label: "Chichewa" },
  { code: "zh-CN", label: "Chinese (Simplified)" },
  { code: "zh-TW", label: "Chinese (Traditional)" },
  { code: "co", label: "Corsican" },
  { code: "hr", label: "Croatian" },
  { code: "cs", label: "Czech" },
  { code: "da", label: "Danish" },
  { code: "nl", label: "Dutch" },
  { code: "en", label: "English" },
  { code: "de", label: "German" },
  { code: "pt-BR", label: "Portuguese (Brazil)" },
  { code: "pt", label: "Portuguese" },
  { code: "es", label: "Spanish" },
  { code: "fr", label: "French" },
  { code: "it", label: "Italian" },
  { code: "eo", label: "Esperanto" },
  { code: "et", label: "Estonian" },
  { code: "fi", label: "Finnish" },
  { code: "fy", label: "Frisian" },
  { code: "gl", label: "Galician" },
  { code: "ka", label: "Georgian" },
  { code: "el", label: "Greek" },
  { code: "gu", label: "Gujarati" },
  { code: "ht", label: "Haitian Creole" },
  { code: "ha", label: "Hausa" },
  { code: "haw", label: "Hawaiian" },
  { code: "hi", label: "Hindi" },
  { code: "hmn", label: "Hmong" },
  { code: "hu", label: "Hungarian" },
  { code: "is", label: "Icelandic" },
  { code: "ig", label: "Igbo" },
  { code: "id", label: "Indonesian" },
  { code: "ga", label: "Irish" },
  { code: "ja", label: "Japanese" },
  { code: "jv", label: "Javanese" },
  { code: "kn", label: "Kannada" },
  { code: "kk", label: "Kazakh" },
  { code: "km", label: "Khmer" },
  { code: "rw", label: "Kinyarwanda" },
  { code: "ko", label: "Korean" },
  { code: "ku", label: "Kurdish" },
  { code: "ky", label: "Kyrgyz" },
  { code: "lo", label: "Lao" },
  { code: "la", label: "Latin" },
  { code: "lv", label: "Latvian" },
  { code: "lt", label: "Lithuanian" },
  { code: "lb", label: "Luxembourgish" },
  { code: "mk", label: "Macedonian" },
  { code: "mg", label: "Malagasy" },
  { code: "ms", label: "Malay" },
  { code: "ml", label: "Malayalam" },
  { code: "mt", label: "Maltese" },
  { code: "mi", label: "Maori" },
  { code: "mr", label: "Marathi" },
  { code: "mn", label: "Mongolian" },
  { code: "my", label: "Myanmar (Burmese)" },
  { code: "ne", label: "Nepali" },
  { code: "no", label: "Norwegian" },
  { code: "or", label: "Odia" },
  { code: "ps", label: "Pashto" },
  { code: "fa", label: "Persian" },
  { code: "pl", label: "Polish" },
  { code: "pa", label: "Punjabi" },
  { code: "ro", label: "Romanian" },
  { code: "ru", label: "Russian" },
  { code: "gd", label: "Scots Gaelic" },
  { code: "sr", label: "Serbian" },
  { code: "st", label: "Sesotho" },
  { code: "sn", label: "Shona" },
  { code: "sd", label: "Sindhi" },
  { code: "si", label: "Sinhala" },
  { code: "sk", label: "Slovak" },
  { code: "sl", label: "Slovenian" },
  { code: "so", label: "Somali" },
  { code: "su", label: "Sundanese" },
  { code: "sw", label: "Swahili" },
  { code: "sv", label: "Swedish" },
  { code: "tg", label: "Tajik" },
  { code: "ta", label: "Tamil" },
  { code: "te", label: "Telugu" },
  { code: "th", label: "Thai" },
  { code: "tr", label: "Turkish" },
  { code: "uk", label: "Ukrainian" },
  { code: "ur", label: "Urdu" },
  { code: "uz", label: "Uzbek" },
  { code: "vi", label: "Vietnamese" },
  { code: "cy", label: "Welsh" },
  { code: "xh", label: "Xhosa" },
  { code: "yi", label: "Yiddish" },
  { code: "yo", label: "Yoruba" },
  { code: "zu", label: "Zulu" },
  { code: "he", label: "Hebrew" },
  { code: "fil", label: "Filipino" },
];

const setGoogleTranslateCookie = (languageCode: string) => {
  if (typeof document === "undefined") return;
  const safeLanguage = toGoogleTranslateCode(languageCode || "en");
  document.cookie = `googtrans=/auto/${safeLanguage}; path=/; SameSite=Lax`;
};

export const getStoredAppLanguage = () => {
  if (typeof window === "undefined") return "en";
  
  // Try to get from new preferences system first
  try {
    const { getLanguage } = require("./userPreferencesStorage");
    const language = getLanguage();
    if (language) return language;
  } catch (error) {
    // Fallback to old method if new system not available
    const saved = localStorage.getItem(APP_LANGUAGE_STORAGE_KEY);
    if (saved) return saved;
  }
  
  return "en";
};

export const applyStoredAppLanguage = (languageCode: string) => {
  if (typeof window === "undefined") return;
  const safeLanguage = normalizeLanguageTag(languageCode || "en");
  
  // Save to new preferences system
  try {
    const { setLanguage } = require("./userPreferencesStorage");
    setLanguage(safeLanguage);
  } catch (error) {
    // Fallback to old method
    localStorage.setItem(APP_LANGUAGE_STORAGE_KEY, safeLanguage);
  }
  
  setGoogleTranslateCookie(safeLanguage);
  document.documentElement.lang = safeLanguage;
};

