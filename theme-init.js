(function () {
  var choice = 'dark';
  try { var saved = localStorage.getItem('cadrivolt-theme'); if (saved === 'light' || saved === 'dark' || saved === 'auto') choice = saved; } catch (_) {}
  var dark = choice === 'dark' || (choice === 'auto' && window.matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
})();
