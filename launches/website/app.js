/* ═══════════════════════════════════════════════════════════════════════════
   CLIPLAN — Main Application JavaScript
   Handles: Scroll animations, particles, navigation, download logic,
            counters, smooth scroll, and loading screen.
   ═══════════════════════════════════════════════════════════════════════════ */

(function () {
  'use strict';

  // ── Loading Screen ──────────────────────────────────────────────────────
  window.addEventListener('load', () => {
    const loader = document.getElementById('loader');
    setTimeout(() => loader.classList.add('hidden'), 800);
    setTimeout(() => loader.remove(), 1400);
  });

  // ── Navbar Scroll Effect ────────────────────────────────────────────────
  const navbar = document.getElementById('navbar');
  let lastScroll = 0;

  function handleNavScroll() {
    const currentScroll = window.scrollY;
    if (currentScroll > 50) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
    lastScroll = currentScroll;
  }
  window.addEventListener('scroll', handleNavScroll, { passive: true });

  // ── Mobile Navigation Toggle ────────────────────────────────────────────
  const navToggle = document.getElementById('navToggle');
  const navLinks = document.getElementById('navLinks');

  navToggle.addEventListener('click', () => {
    navToggle.classList.toggle('open');
    navLinks.classList.toggle('open');
  });

  // Close menu on link click
  navLinks.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => {
      navToggle.classList.remove('open');
      navLinks.classList.remove('open');
    });
  });

  // ── Smooth Scroll for Anchor Links ──────────────────────────────────────
  document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
    anchor.addEventListener('click', (e) => {
      e.preventDefault();
      const target = document.querySelector(anchor.getAttribute('href'));
      if (target) {
        const offset = 80;
        const top = target.getBoundingClientRect().top + window.scrollY - offset;
        window.scrollTo({ top, behavior: 'smooth' });
      }
    });
  });

  // ── Scroll-Triggered Reveal Animations ──────────────────────────────────
  const revealElements = document.querySelectorAll(
    '.reveal, .reveal-left, .reveal-right, .reveal-scale'
  );

  const revealObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('active');
          revealObserver.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.1, rootMargin: '0px 0px -60px 0px' }
  );

  revealElements.forEach((el) => revealObserver.observe(el));

  // ── Animated Counters ───────────────────────────────────────────────────
  const counters = document.querySelectorAll('.counter');
  const counterObserver = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          animateCounter(entry.target);
          counterObserver.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.5 }
  );
  counters.forEach((c) => counterObserver.observe(c));

  function animateCounter(el) {
    const target = parseInt(el.dataset.target, 10);
    if (isNaN(target)) return;
    const duration = 2000;
    const step = target / (duration / 16);
    let current = 0;

    function update() {
      current += step;
      if (current >= target) {
        el.textContent = target + '+';
        return;
      }
      el.textContent = Math.floor(current) + '+';
      requestAnimationFrame(update);
    }
    update();
  }

  // ── Active Nav Link Highlighting ────────────────────────────────────────
  const sections = document.querySelectorAll('section[id]');

  function highlightNav() {
    const scrollPos = window.scrollY + 120;
    sections.forEach((sec) => {
      const top = sec.offsetTop;
      const height = sec.offsetHeight;
      const id = sec.getAttribute('id');
      const link = document.querySelector(`.nav-links a[href="#${id}"]`);

      if (link) {
        if (scrollPos >= top && scrollPos < top + height) {
          link.classList.add('active');
        } else {
          link.classList.remove('active');
        }
      }
    });
  }
  window.addEventListener('scroll', highlightNav, { passive: true });

  // ── Particle Canvas ─────────────────────────────────────────────────────
  const canvas = document.getElementById('particles');
  if (canvas) {
    const ctx = canvas.getContext('2d');
    let particles = [];
    let animFrame;

    function resize() {
      const hero = document.getElementById('hero');
      if (!hero) return;
      canvas.width = hero.offsetWidth;
      canvas.height = hero.offsetHeight;
    }

    class Particle {
      constructor() {
        this.reset();
      }
      reset() {
        this.x = Math.random() * canvas.width;
        this.y = Math.random() * canvas.height;
        this.vx = (Math.random() - 0.5) * 0.3;
        this.vy = (Math.random() - 0.5) * 0.3;
        this.radius = Math.random() * 1.5 + 0.5;
        this.opacity = Math.random() * 0.5 + 0.1;
        this.life = Math.random() * 200 + 100;
        this.maxLife = this.life;
      }
      update() {
        this.x += this.vx;
        this.y += this.vy;
        this.life--;
        this.opacity = (this.life / this.maxLife) * 0.4;
        if (this.life <= 0 || this.x < 0 || this.x > canvas.width || this.y < 0 || this.y > canvas.height) {
          this.reset();
        }
      }
      draw() {
        ctx.beginPath();
        ctx.arc(this.x, this.y, this.radius, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(91, 163, 245, ${this.opacity})`;
        ctx.fill();
      }
    }

    function initParticles() {
      const count = Math.min(80, Math.floor(canvas.width * canvas.height / 15000));
      particles = [];
      for (let i = 0; i < count; i++) {
        particles.push(new Particle());
      }
    }

    function drawLines() {
      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const dx = particles[i].x - particles[j].x;
          const dy = particles[i].y - particles[j].y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < 120) {
            ctx.beginPath();
            ctx.moveTo(particles[i].x, particles[i].y);
            ctx.lineTo(particles[j].x, particles[j].y);
            ctx.strokeStyle = `rgba(59, 130, 246, ${0.06 * (1 - dist / 120)})`;
            ctx.lineWidth = 0.5;
            ctx.stroke();
          }
        }
      }
    }

    function animate() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      particles.forEach((p) => {
        p.update();
        p.draw();
      });
      drawLines();
      animFrame = requestAnimationFrame(animate);
    }

    resize();
    initParticles();
    animate();

    window.addEventListener('resize', () => {
      resize();
      initParticles();
    });
  }

  // ── Auto-scroll Screenshots Gallery ─────────────────────────────────────
  const gallery = document.getElementById('screenshotGallery');
  if (gallery) {
    let scrollInterval;
    let scrollDir = 1;

    function autoScrollGallery() {
      scrollInterval = setInterval(() => {
        gallery.scrollLeft += scrollDir * 1;
        if (gallery.scrollLeft >= gallery.scrollWidth - gallery.clientWidth - 10) {
          scrollDir = -1;
        } else if (gallery.scrollLeft <= 10) {
          scrollDir = 1;
        }
      }, 30);
    }

    const galleryObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            autoScrollGallery();
          } else {
            clearInterval(scrollInterval);
          }
        });
      },
      { threshold: 0.3 }
    );
    galleryObserver.observe(gallery);

    // Pause on hover
    gallery.addEventListener('mouseenter', () => clearInterval(scrollInterval));
    gallery.addEventListener('mouseleave', () => {
      clearInterval(scrollInterval);
      autoScrollGallery();
    });
  }

  // ── Download Logic ──────────────────────────────────────────────────────
  window.downloadFile = function (platform) {
    const modal = document.getElementById('downloadModal');
    const title = document.getElementById('modalTitle');
    const desc = document.getElementById('modalDesc');
    const actions = document.getElementById('modalActions');

    const downloads = {
      android: {
        title: '📱 Download for Android',
        desc: 'Get the ClipLAN APK for your Android device.',
        file: 'ClipLAN-v1.0.0.apk',
        ext: '.apk',
      },
      macos: {
        title: '🍎 Download for macOS',
        desc: 'Get the ClipLAN disk image for your Mac.',
        file: 'ClipLAN-v1.0.0.dmg',
        ext: '.dmg',
      },
      windows: {
        title: '🪟 Download for Windows',
        desc: 'Get the ClipLAN installer for Windows.',
        file: 'ClipLAN-v1.0.0.exe',
        ext: '.exe',
      },
    };

    const info = downloads[platform];
    if (!info) return;

    title.textContent = info.title;
    desc.textContent = info.desc;
    actions.innerHTML = `
      <a href="downloads/${info.file}" download class="btn btn-primary" onclick="closeModal()">
        <span class="btn-icon">⬇</span>
        Download ${info.ext}
      </a>
      <button class="btn btn-outline" onclick="closeModal()">Cancel</button>
    `;

    modal.classList.add('active');
  };

  window.closeModal = function (id) {
    if (id) {
      document.getElementById(id).classList.remove('active');
    } else {
      document.getElementById('downloadModal').classList.remove('active');
    }
  };

  window.openModal = function (id) {
    document.getElementById(id).classList.add('active');
  };

  // Close modal on backdrop click
  document.querySelectorAll('.modal-overlay').forEach(modal => {
    modal.addEventListener('click', (e) => {
      if (e.target === e.currentTarget) {
        modal.classList.remove('active');
      }
    });
  });

  // ── Animated Scroll Background ──────────────────────────────────────────
  // Background animation is now handled entirely by CSS keyframes and background-attachment: fixed


  // ── OS Auto-Detection ───────────────────────────────────────────────────
  function detectOS() {
    const ua = navigator.userAgent.toLowerCase();
    if (ua.includes('android')) return 'android';
    if (ua.includes('mac')) return 'macos';
    if (ua.includes('win')) return 'windows';
    if (ua.includes('iphone') || ua.includes('ipad')) return 'ios';
    if (ua.includes('linux')) return 'linux';
    return 'unknown';
  }

  // Highlight the user's platform card
  const userOS = detectOS();
  const platformCards = document.querySelectorAll('.platform-card');
  const platformMap = { android: 0, macos: 1, windows: 2 };
  if (platformMap[userOS] !== undefined && platformCards[platformMap[userOS]]) {
    const card = platformCards[platformMap[userOS]];
    // Add "Recommended" badge
    const badge = document.createElement('div');
    badge.textContent = '✦ Recommended for your device';
    badge.style.cssText =
      'font-size:0.8rem;color:var(--primary-light);margin-bottom:16px;font-weight:600;';
    card.insertBefore(badge, card.querySelector('h3'));
  }

  // ── Keyboard Navigation ─────────────────────────────────────────────────
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      document.querySelectorAll('.modal-overlay.active').forEach(modal => {
        modal.classList.remove('active');
      });
    }
  });

})();
