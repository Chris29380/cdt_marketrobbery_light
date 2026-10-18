(() => {
  const link = document.querySelector('.acstudio-link');
  if (!link) return;
  link.addEventListener('click', (event) => {
    if (typeof window.invokeNative === 'function') {
      event.preventDefault();
      window.invokeNative('openUrl', 'https://acstudio.cdtfivem.com');
    }
  });
})();
