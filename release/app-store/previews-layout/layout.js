const response = await fetch('../preview-art-direction.json');
if (!response.ok) throw new Error('Unable to load the approved preview copy.');
const direction = await response.json();
const pageNumber = Number(new URLSearchParams(location.search).get('page'));
function createPoster(page, index) {
  const poster = document.createElement('article');
  poster.className = 'poster';
  poster.setAttribute('aria-label', page.headline.join(''));
  const header = document.createElement('header');
  header.className = 'poster-header';
  const brandLine = document.createElement('div');
  brandLine.className = 'brand-line';
  const wordmark = document.createElement('div');
  wordmark.className = 'wordmark'; wordmark.textContent = 'つつうら';
  const sequence = document.createElement('div');
  sequence.className = 'sequence'; sequence.textContent = `${String(index + 1).padStart(2, '0')} / 04`;
  brandLine.append(wordmark, sequence);
  const headline = document.createElement('h1');
  for (const [lineIndex, text] of page.headline.entries()) {
    const line = document.createElement('span');
    if (lineIndex === 1) line.className = 'accent';
    line.textContent = text;
    headline.append(line);
  }
  const subline = document.createElement('p');
  subline.className = 'subline'; subline.textContent = page.subline;
  header.append(brandLine, headline, subline);
  const frame = document.createElement('figure'); frame.className = 'screen-frame';
  const screenshot = document.createElement('img');
  screenshot.src = `../${page.source}`;
  screenshot.alt = ['家族の回答が並ぶホーム画面', '文章・音声・写真で回答する画面', '過去の回答を振り返る画面', '自分のしるしをかく画面'][index];
  screenshot.width = 1320; screenshot.height = 2868;
  screenshot.dataset.sourceSha256 = page.sourceSHA256;
  frame.append(screenshot); poster.append(header, frame);
  return poster;
}
if (pageNumber >= 1 && pageNumber <= 4) {
  document.title = `つつうら — App Store ${pageNumber}/4`;
  document.body.append(createPoster(direction.pages[pageNumber - 1], pageNumber - 1));
} else {
  document.body.className = 'gallery';
  const title = document.createElement('div'); title.className = 'gallery-heading';
  title.textContent = 'つつうら · App Store プレビュー';
  const grid = document.createElement('main'); grid.className = 'gallery-grid';
  for (const [index, page] of direction.pages.entries()) {
    const link = document.createElement('a'); link.className = 'gallery-card'; link.href = `?page=${index + 1}`;
    const wrapper = document.createElement('div'); wrapper.className = 'gallery-poster';
    const poster = createPoster(page, index); wrapper.append(poster);
    const label = document.createElement('div'); label.className = 'gallery-label';
    label.textContent = `${String(index + 1).padStart(2, '0')} — ${page.headline.join('')}`;
    link.append(wrapper, label); grid.append(link);
    new ResizeObserver(() => { poster.style.transform = `scale(${wrapper.clientWidth / 1320})`; }).observe(wrapper);
  }
  document.body.append(title, grid);
}
await document.fonts.ready;
await Promise.all(Array.from(document.images, image => image.decode()));
document.documentElement.dataset.ready = 'true';
