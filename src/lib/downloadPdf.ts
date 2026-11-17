const safeFilename = (value: string) => {
  const normalised = value.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
  const slug = normalised
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);

  return slug || 'fitxa-museu';
};

const waitForImages = async (element: HTMLElement) => {
  const images = [...element.querySelectorAll('img')];
  await Promise.all(images.map(async (image) => {
    if (!image.complete) {
      await new Promise<void>((resolve) => {
        image.addEventListener('load', () => resolve(), { once: true });
        image.addEventListener('error', () => resolve(), { once: true });
      });
    }
    try { await image.decode(); } catch { /* Una imatge opcional no ha d'impedir la fitxa. */ }
  }));
};

/** Crea un PDF A4 en color sense obrir el diàleg d'impressió del navegador. */
export const downloadPdf = async (element: HTMLElement, title: string) => {
  await waitForImages(element);
  const [{ default: html2canvas }, { jsPDF }] = await Promise.all([
    import('html2canvas'),
    import('jspdf')
  ]);
  element.setAttribute('data-pdf-export', '');
  let canvas: HTMLCanvasElement;
  try {
    canvas = await html2canvas(element, {
      backgroundColor: '#ffffff',
      scale: Math.min(window.devicePixelRatio || 1, 2),
      useCORS: true,
      logging: false,
      ignoreElements: (node) => node.classList?.contains('no-print') || node.hasAttribute?.('data-pdf-status'),
      onclone: (document) => {
        const style = document.createElement('style');
        style.textContent = `
          [data-pdf-export] {
            width: 718px !important;
            max-width: none !important;
            margin: 0 !important;
            padding: 6px !important;
            background: #ffffff !important;
            color: #111111 !important;
            font-size: 16px !important;
            line-height: 1.45 !important;
          }
          [data-pdf-export] h1,
          [data-pdf-export] h2,
          [data-pdf-export] h3,
          [data-pdf-export] .lead,
          [data-pdf-export] .detail-story p,
          [data-pdf-export] .detail-meta dd,
          [data-pdf-export] .figure-editorial section > div,
          [data-pdf-export] .figure-sources { color: #111111 !important; }
          [data-pdf-export] em { color: #315a3a !important; }
          [data-pdf-export] .eyebrow,
          [data-pdf-export] .detail-meta dt,
          [data-pdf-export] .figure-sheet-header,
          [data-pdf-export] .figure-sheet-footer { color: #315a3a !important; }
          [data-pdf-export] .detail-visual,
          [data-pdf-export] .detail-visual img,
          [data-pdf-export] .detail-visual[data-gallery] img,
          [data-pdf-export] .figure-portrait,
          [data-pdf-export] .detail-meta div {
            background: #f3f5f2 !important;
            border-color: #667068 !important;
          }
          [data-pdf-export] .hashtag { background: #f3f5f2 !important; color: #315a3a !important; }
          [data-pdf-export] .detail-hero { grid-template-columns: 280px minmax(0, 1fr) !important; gap: 28px !important; margin-top: 0 !important; }
          [data-pdf-export] .detail-hero h1,
          [data-pdf-export] .figure-detail h1 { font-size: 42px !important; }
          [data-pdf-export] .lead { font-size: 18px !important; }

          /* Fitxa de catàleg: resum, foto principal i metadades essencials. */
          [data-pdf-export].detail-page .detail-visual[data-gallery] figure:nth-of-type(n + 2),
          [data-pdf-export].detail-page [data-history],
          [data-pdf-export].detail-page .detail-meta > div:nth-child(n + 6) { display: none !important; }
          [data-pdf-export].detail-page .detail-story { margin-top: 28px !important; }
          [data-pdf-export].detail-page .detail-story h2,
          [data-pdf-export].detail-page [data-meta-section] h2 { font-size: 25px !important; }
          [data-pdf-export].detail-page .detail-story p { font-size: 16px !important; }

          /* Fitxa biogràfica: contingut editorial principal, sense bibliografia. */
          [data-pdf-export] .figure-sheet { width: 670px !important; max-width: none !important; }
          [data-pdf-export] .figure-detail-hero { grid-template-columns: 205px minmax(0, 1fr) !important; gap: 28px !important; padding-block: 24px !important; }
          [data-pdf-export] .figure-editorial { gap: 24px !important; padding-block: 20px !important; }
          [data-pdf-export] .figure-sources { display: none !important; }
          [data-pdf-export] [data-biography] p:not(:first-child),
          [data-pdf-export] [data-contribution] p:not(:first-child) { display: none !important; }
          [data-pdf-export] [data-biography] p:first-child,
          [data-pdf-export] [data-contribution] p:first-child {
            display: -webkit-box !important;
            overflow: hidden !important;
            -webkit-box-orient: vertical !important;
            -webkit-line-clamp: 7 !important;
          }
        `;
        document.head.append(style);
      }
    });
  } finally {
    element.removeAttribute('data-pdf-export');
  }
  const pdf = new jsPDF({ format: 'a4', orientation: 'portrait', unit: 'mm', compress: true });
  const pageWidth = 210;
  const pageHeight = 297;
  const margin = 10;
  const contentWidth = pageWidth - margin * 2;
  const contentHeight = pageHeight - margin * 2;
  const scale = Math.min(contentWidth / canvas.width, contentHeight / canvas.height);
  const imageWidth = canvas.width * scale;
  const imageHeight = canvas.height * scale;
   const x = (pageWidth - imageWidth) / 2;
   const y = margin;
  pdf.addImage(canvas.toDataURL('image/jpeg', 0.92), 'JPEG', x, y, imageWidth, imageHeight, undefined, 'FAST');

  pdf.save(`${safeFilename(title)}.pdf`);
};
