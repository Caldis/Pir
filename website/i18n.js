import en from './locales/en.json';
import zh from './locales/zh.json';
const messages = { en, zh };
let language = navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en';
try { const saved = localStorage.getItem('pir-language'); if (saved in messages) language = saved; } catch {}
export function t(key) { return messages[language][key] ?? en[key] ?? key; }
function applyLanguage() {
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
  document.title = t('title');
  for (const attribute of ['description', 'og:description', 'og:title']) {
    document.querySelector(`meta[${attribute.startsWith('og:') ? 'property' : 'name'}="${attribute}"]`)
      ?.setAttribute('content', t(attribute === 'og:title' ? 'title' : 'description'));
  }
  for (const element of document.querySelectorAll('[data-i18n]')) element.innerHTML = t(element.dataset.i18n);
  for (const attribute of ['aria-label', 'alt']) {
    for (const element of document.querySelectorAll(`[data-i18n-${attribute}]`)) {
      element.setAttribute(attribute, t(element.getAttribute(`data-i18n-${attribute}`)));
    }
  }
  const toggle = document.querySelector('#language-toggle');
  toggle.textContent = language === 'zh' ? 'EN' : '中文';
  toggle.setAttribute('aria-label', language === 'zh' ? 'Switch to English' : '切换为简体中文');
  document.dispatchEvent(new Event('pir-languagechange'));
}
document.querySelector('#language-toggle').addEventListener('click', () => {
  language = language === 'zh' ? 'en' : 'zh';
  try { localStorage.setItem('pir-language', language); } catch {}
  applyLanguage();
});
applyLanguage();
