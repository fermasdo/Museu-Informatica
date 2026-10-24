export type Announcement = {
  title: string;
  year: number;
  category: 'Ordinador personal' | 'Consola' | 'Videojoc' | 'Programari';
  description: string;
  youtubeUrl: string;
};

export const announcements: Announcement[] = [
  { title: 'Olivetti Programma 101', year: 1965, category: 'Ordinador personal', description: 'Un anunci de la calculadora programable que anticipava l’ordinador de sobretaula.', youtubeUrl: 'https://www.youtube.com/results?search_query=Olivetti+Programma+101+commercial' },
  { title: 'Atari 2600', year: 1977, category: 'Consola', description: 'La consola que va portar l’arcade al menjador de casa.', youtubeUrl: 'https://www.youtube.com/results?search_query=Atari+2600+television+commercial' },
  { title: 'Pac-Man', year: 1980, category: 'Videojoc', description: 'Una icona recreativa explicada a través de la publicitat de la seua època.', youtubeUrl: 'https://www.youtube.com/results?search_query=Pac-Man+1980+television+commercial' },
  { title: 'Sinclair ZX Spectrum', year: 1982, category: 'Ordinador personal', description: 'Color, BASIC i un ordinador que va obrir la porta de moltes habitacions.', youtubeUrl: 'https://www.youtube.com/results?search_query=Sinclair+ZX+Spectrum+commercial' },
  { title: 'Super Mario Bros.', year: 1985, category: 'Videojoc', description: 'El salt de Nintendo cap a una nova generació de joc domèstic.', youtubeUrl: 'https://www.youtube.com/results?search_query=Super+Mario+Bros+1985+commercial' },
  { title: 'Commodore Amiga', year: 1987, category: 'Ordinador personal', description: 'Gràfics, so i creativitat en una campanya que celebrava les possibilitats multimèdia.', youtubeUrl: 'https://www.youtube.com/results?search_query=Commodore+Amiga+commercial' },
  { title: 'Game Boy', year: 1989, category: 'Consola', description: 'La consola portàtil que va convertir els trajectes en partides.', youtubeUrl: 'https://www.youtube.com/results?search_query=Game+Boy+1989+commercial' },
  { title: 'Sonic the Hedgehog', year: 1991, category: 'Videojoc', description: 'Velocitat i identitat Sega en la batalla dels 16 bits.', youtubeUrl: 'https://www.youtube.com/results?search_query=Sonic+the+Hedgehog+1991+commercial' },
  { title: 'Windows 95', year: 1995, category: 'Programari', description: 'Una campanya global per a una interfície que entrava a milions de llars.', youtubeUrl: 'https://www.youtube.com/results?search_query=Windows+95+commercial' },
  { title: 'PlayStation 2', year: 2000, category: 'Consola', description: 'La consola com a centre d’entreteniment de la nova dècada.', youtubeUrl: 'https://www.youtube.com/results?search_query=PlayStation+2+commercial' },
  { title: 'Nintendo DS', year: 2005, category: 'Consola', description: 'Dues pantalles per jugar d’una manera diferent.', youtubeUrl: 'https://www.youtube.com/results?search_query=Nintendo+DS+2005+commercial' }
];
