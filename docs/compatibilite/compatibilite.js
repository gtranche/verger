// La liste de compatibilite des jeux : lit jeux.json (Scripts/compatibilite.py),
// filtre par recherche, etat et provenance, et l'affiche par pages de 60.
// « Mon Mac » (memorise dans le navigateur) choisit l'etat affiche : les
// conditions `si` des fiches ([[compat.machines]], [[machine]]) sont evaluees
// comme Cidre les evalue, sur ce qu'on sait d'une puce (famille Metal,
// generation, gamme, plage de coeurs GPU) ; un fait qu'on ne sait pas (l'ecran)
// laisse la condition « selon votre Mac ».
// Partage par la page francaise (compatibilite/) et anglaise (en/compatibility/) :
// la langue est celle de <html lang>, le chemin des donnees celui de data-donnees.
(function () {
  "use strict";

  var racine = document.getElementById("compat");
  if (!racine) return;
  var en = document.documentElement.lang === "en";

  var T = en ? {
    etats: { "or": "Gold", "argent": "Silver", "bronze": "Bronze", "ko": "Broken", "non-teste": "Untested" },
    explications: { "or": "Perfect", "argent": "Playable, with limits", "bronze": "Starts, but slow or buggy", "ko": "Does not work", "non-teste": "Not tried with Cidre yet" },
    origines: { t: "Validated by Cidre", d: "Cidre profile", c: "Imported report" },
    paliers: { platinum: "Platinum", gold: "Gold", silver: "Silver", bronze: "Bronze", borked: "Borked", pending: "Pending" },
    agw: { parfait: "perfect", jouable: "playable", demarre: "runs", ko: "unplayable" },
    natif: "Native",
    jeux: function (n) { return n === 1 ? "1 game" : fmt(n) + " games"; },
    sur: function (n, total) { return fmt(n) + " of " + fmt(total) + (total === 1 ? " game" : " games"); },
    plus: function (n) { return "Show " + fmt(n) + " more"; },
    aucun: "No game matches. Try another spelling, or the Steam appid.",
    chargement: "Loading the list…",
    erreur: "The list could not be loaded.",
    rendu: "Rendering", api: "Game API", moteur: "Engine", anticheat: "Anti-cheat",
    mesure: "Measured", menu: "menu", jeu: "in game", ips: "fps", sur_machine: "on",
    familles: "By Mac family", options: "Options",
    linux: "ProtonDB (Linux)", rapports: function (n) { return fmt(n) + " reports"; },
    tous_mac: "Any Mac", mon_mac: "My Mac", detecte: "detected by your browser, change it if wrong",
    pour_mac: function (m) { return "Ratings for " + m.nom + " (" + famille(m.famille) + ")."; },
    pour_tous: "Ratings as measured on the reference Mac. Pick your Mac to see the rating for it.",
    sans_machine: "ProtonDB and AppleGamingWiki ratings say nothing about your Mac: ProtonDB is Linux, AppleGamingWiki does not say which Mac.",
    linux_court: "Linux", linux_titre: "ProtonDB tier: measured on Linux PCs and Steam Decks, not on a Mac",
    mac_inconnu: "Mac not stated",
    mesure_sur: function (m) { return "Measured on " + m; },
    pour_entree: function (n) { return "rating for “" + n + "”"; },
    pas_essaye: function (m) { return "not tried on " + m + " yet"; },
    voir_dessous: function (m) { return "this path not measured on " + m + " yet, other results below"; },
    votre_mac: "your Mac", meme_famille: "your Mac family",
    autres_voies: "Other paths on your Mac", selon: "Depends on your Mac",
    si_mots: { famille_gpu: "Metal family", generation: "chip generation", gamme: "tier", coeurs_gpu: "GPU cores",
      memoire_go: "memory (GB)", macos: "macOS", ecran_largeur: "screen width (points)", ecran_hauteur: "screen height (points)" },
    si: "if", et: "and",
    reglages_mac: "Settings Cidre applies on your Mac", reglages_selon: "Settings by machine",
    lancement: "Launch", jeu_reglages: "Game settings",
    rapports_titre: "Player reports", sans_famille: "family unknown",
    incident: "report",
    crossover: "CrossOver", wine: "Wine/GPTK",
    steam: "Steam store page", protondb: "ProtonDB page", agw_page: "AppleGamingWiki page",
    cidre_version: "Cidre"
  } : {
    etats: { "or": "Or", "argent": "Argent", "bronze": "Bronze", "ko": "Ne marche pas", "non-teste": "Non testé" },
    explications: { "or": "Parfait", "argent": "Jouable avec des limites", "bronze": "Démarre mais lent ou bogué", "ko": "Ne marche pas", "non-teste": "Pas encore essayé avec Cidre" },
    origines: { t: "Validé Cidre", d: "Fiche Cidre", c: "Rapport importé" },
    paliers: { platinum: "Platine", gold: "Or", silver: "Argent", bronze: "Bronze", borked: "Ne marche pas", pending: "En attente" },
    agw: { parfait: "parfait", jouable: "jouable", demarre: "démarre", ko: "ne marche pas" },
    natif: "Natif",
    jeux: function (n) { return n === 1 ? "1 jeu" : fmt(n) + " jeux"; },
    sur: function (n, total) { return (n === 1 ? "1 jeu" : fmt(n) + " jeux") + " sur " + fmt(total); },
    plus: function (n) { return "Afficher " + fmt(n) + " de plus"; },
    aucun: "Aucun jeu ne correspond. Essaie une autre orthographe, ou l'appid Steam.",
    chargement: "Chargement de la liste…",
    erreur: "La liste n'a pas pu être chargée.",
    rendu: "Rendu", api: "API du jeu", moteur: "Moteur", anticheat: "Anti-triche",
    mesure: "Mesuré", menu: "menu", jeu: "en jeu", ips: "i/s", sur_machine: "sur",
    familles: "Par famille de Mac", options: "Options",
    linux: "ProtonDB (Linux)", rapports: function (n) { return fmt(n) + " rapports"; },
    tous_mac: "Tous les Mac", mon_mac: "Mon Mac", detecte: "détecté par le navigateur, à corriger s'il se trompe",
    pour_mac: function (m) { return "États pour un " + m.nom + " (" + famille(m.famille) + ")."; },
    pour_tous: "États tels que mesurés sur le Mac de référence. Choisis ton Mac pour voir l'état sur le tien.",
    sans_machine: "Les notes ProtonDB et AppleGamingWiki ne disent rien de ton Mac : ProtonDB, c'est Linux, et AppleGamingWiki ne dit pas sur quel Mac.",
    linux_court: "Linux", linux_titre: "Palier ProtonDB : mesuré sur PC Linux et Steam Deck, pas sur Mac",
    mac_inconnu: "Mac non précisé",
    mesure_sur: function (m) { return "Mesuré sur " + m; },
    pour_entree: function (n) { return "état « " + n + " »"; },
    pas_essaye: function (m) { return "pas encore essayé sur " + m; },
    voir_dessous: function (m) { return "cette voie pas encore mesurée sur " + m + ", autres résultats ci-dessous"; },
    votre_mac: "ton Mac", meme_famille: "ta famille de Mac",
    autres_voies: "Autres voies sur ton Mac", selon: "Selon ton Mac",
    si_mots: { famille_gpu: "famille Metal", generation: "génération de puce", gamme: "gamme", coeurs_gpu: "cœurs GPU",
      memoire_go: "mémoire (Go)", macos: "macOS", ecran_largeur: "largeur d'écran (points)", ecran_hauteur: "hauteur d'écran (points)" },
    si: "si", et: "et",
    reglages_mac: "Réglages que Cidre pose sur ton Mac", reglages_selon: "Réglages selon la machine",
    lancement: "Lancement", jeu_reglages: "Réglages du jeu",
    rapports_titre: "Rapports de joueurs", sans_famille: "famille inconnue",
    incident: "rapport",
    crossover: "CrossOver", wine: "Wine/GPTK",
    steam: "Page du magasin Steam", protondb: "Page ProtonDB", agw_page: "Page AppleGamingWiki",
    cidre_version: "Cidre"
  };

  var VOIES = { dxmt: "Direct3D 11 (DXMT)", dxvk: "Direct3D 11 (DXVK)", d3d12: "Direct3D 12", wined3d: "WineD3D" };
  var APIS = { d3d12: "Direct3D 12", d3d11: "Direct3D 11", d3d10: "Direct3D 10", d3d9: "Direct3D 9", d3d8: "Direct3D 8",
    d3d7: "Direct3D 7", d3d6: "Direct3D 6", d3d5: "Direct3D 5", d3d3: "Direct3D 3", ddraw: "DirectDraw", opengl: "OpenGL", vulkan: "Vulkan" };
  var MOTEURS = { unity: "Unity", unreal: "Unreal", source: "Source", godot: "Godot", hashlink: "HashLink", stingray: "Stingray" };
  var ANTICHEATS = { eac: "Easy Anti-Cheat", battleye: "BattlEye", denuvo: "Denuvo", vac: "VAC" };
  var RANG_ETAT = { "or": 0, "argent": 1, "bronze": 2, "ko": 3, "non-teste": 4 };
  var RANG_ORIGINE = { t: 0, d: 1, c: 2 };
  var PAGE = 60;

  // Les puces : famille Metal (MTLGPUFamilyApple<N>, fait `famille_gpu` de Cidre :
  // 7 = M1, 8 = M2, 9 = M3 et M4), generation, gamme et plage de coeurs GPU des
  // modeles vendus. Une plage qui chevauche un seuil laisse la condition ouverte.
  var MACS = [
    ["m1", "M1", 1, "base", 7, 7, 8], ["m1-pro", "M1 Pro", 1, "pro", 7, 14, 16],
    ["m1-max", "M1 Max", 1, "max", 7, 24, 32], ["m1-ultra", "M1 Ultra", 1, "ultra", 7, 48, 64],
    ["m2", "M2", 2, "base", 8, 8, 10], ["m2-pro", "M2 Pro", 2, "pro", 8, 16, 19],
    ["m2-max", "M2 Max", 2, "max", 8, 30, 38], ["m2-ultra", "M2 Ultra", 2, "ultra", 8, 60, 76],
    ["m3", "M3", 3, "base", 9, 8, 10], ["m3-pro", "M3 Pro", 3, "pro", 9, 14, 18],
    ["m3-max", "M3 Max", 3, "max", 9, 30, 40], ["m3-ultra", "M3 Ultra", 3, "ultra", 9, 60, 80],
    ["m4", "M4", 4, "base", 9, 8, 10], ["m4-pro", "M4 Pro", 4, "pro", 9, 16, 20],
    ["m4-max", "M4 Max", 4, "max", 9, 32, 40],
    // M5 : famille Apple10 attendue, coeurs des Pro et Max pris larges
    ["m5", "M5", 5, "base", 10, 8, 10], ["m5-pro", "M5 Pro", 5, "pro", 10, 14, 24],
    ["m5-max", "M5 Max", 5, "max", 10, 30, 48]
  ].map(function (m) {
    return { id: m[0], nom: m[1], generation: m[2], gamme: m[3], famille: m[4], coeurs: [m[5], m[6]] };
  });
  var FAMILLES = { 7: "Apple7 : M1", 8: "Apple8 : M2", 9: "Apple9 : M3, M4", 10: "Apple10 : M5" };
  function famille(n) { return FAMILLES[n] || "Apple" + n; }
  // la famille d'une machine ecrite en clair (« iMac M4 24 Go ») : M1 -> 7, M2 -> 8, M3 et M4 -> 9
  function familleDe(texte) {
    var m = /\bM([0-9]{1,2})\b/.exec(texte || "");
    if (!m) return null;
    var g = +m[1];
    return g === 1 ? 7 : g === 2 ? 8 : g <= 4 ? 9 : g === 5 ? 10 : null;
  }

  var champ = racine.querySelector("[data-recherche]");
  var boutonsEtat = racine.querySelectorAll("[data-etat]");
  var choixOrigine = racine.querySelector("[data-origine]");
  var choixMac = racine.querySelector("[data-mac]");
  var noteMac = racine.querySelector("[data-note-mac]");
  var compte = racine.querySelector("[data-compte]");
  var liste = racine.querySelector("[data-liste]");
  var suite = racine.querySelector("[data-suite]");

  var langues = Array.prototype.slice.call(document.querySelectorAll(".langues a:not([aria-current])"));
  langues.forEach(function (a) { a.dataset.base = a.getAttribute("href"); });

  var tous = [];
  var trouves = [];
  var montres = 0;
  var filtre = { q: "", etat: "", origine: "" };
  var mac = null;
  var macDetecte = false;

  function fmt(n) { return n.toLocaleString(en ? "en" : "fr"); }

  // « Éléphant » et « elephant » se trouvent l'un l'autre ; ponctuation ignorée.
  function plier(s) {
    return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  }

  function el(nom, classe, contenu) {
    var e = document.createElement(nom);
    if (classe) e.className = classe;
    if (contenu != null) e.textContent = contenu;
    return e;
  }

  // --- Conditions `si` (profils/README.md de Cidre, « Variantes par machine ») ---
  // Vrai, faux, ou null : on ne sait pas (un fait que la puce ne dit pas).
  function faitsDe(m) {
    return m ? { famille_gpu: m.famille, generation: m.generation, gamme: m.gamme, coeurs_gpu: m.coeurs } : {};
  }

  function comparer(a, op, b) {
    switch (op) {
      case "<=": return a <= b; case ">=": return a >= b; case "<": return a < b;
      case ">": return a > b; case "==": return a === b; case "!=": return a !== b;
    }
    return false;
  }

  function terme(t, faits) {
    var m = /^([a-z_]+)\s*(<=|>=|==|!=|<|>)\s*(\S+)$/.exec(t.trim());
    if (!m) return false;                       // illisible : faux, comme Cidre
    var v = faits[m[1]], op = m[2], b = m[3];
    if (v === undefined) return null;
    if (typeof v === "string") return op === "==" ? v === b : op === "!=" ? v !== b : false;
    b = Number(b);
    if (isNaN(b)) return false;
    if (typeof v === "number") return comparer(v, op, b);
    // une plage [min, max] : vrai ou faux si toute la plage est d'accord
    if (op === "==" || op === "!=") {
      if (v[0] === v[1]) return comparer(v[0], op, b);
      return b < v[0] || b > v[1] ? op === "!=" : null;
    }
    var lo = comparer(v[0], op, b), hi = comparer(v[1], op, b);
    return lo === hi ? lo : null;
  }

  function evaluer(si, faits) {
    var r = true;
    String(si).split(/\s+et\s+/).forEach(function (t) {
      var x = terme(t, faits);
      if (x === false) r = false; else if (x === null && r !== false) r = null;
    });
    return r;
  }

  // La condition en clair, sans ce qu'on sait deja vrai du Mac choisi.
  function condition(si, faits) {
    return String(si).split(/\s+et\s+/).filter(function (t) {
      return terme(t, faits) !== true;
    }).map(function (t) {
      var m = /^([a-z_]+)\s*(<=|>=|==|!=|<|>)\s*(\S+)$/.exec(t.trim());
      if (!m) return t;
      var op = { "<=": "≤", ">=": "≥", "==": "=", "!=": "≠", "<": "<", ">": ">" }[m[2]];
      return (T.si_mots[m[1]] || m[1]) + " " + op + " " + m[3];
    }).join(" " + T.et + " ");
  }

  // L'etat d'un jeu sur le Mac choisi, comme Cidre le calcule (README, « Compatibilite
  // par famille de Mac ») : la voie de la fiche sur ce Mac (variantes fondues), puis
  // les entrees [[compat.machines]] vraies de cette voie, la derniere gagnant.
  function surMac(j) {
    var faits = faitsDe(mac);
    var r = { etat: j.etat, mesure: j, voie: j.voie, entree: null, autres: [], possibles: [], ecart: false };
    if (!mac) return r;
    var dx12 = j.voie === "d3d12", d3d11 = dx12 ? null : j.voie;
    (j.variantes || []).forEach(function (v) {
      if (evaluer(v.si, faits) !== true) return;
      if (v.dx12 !== undefined) dx12 = v.dx12;
      if (v.d3d11) d3d11 = v.d3d11;
    });
    if (j.voie) r.voie = dx12 ? "d3d12" : (d3d11 || j.voie);
    if (j.o !== "t") return r;
    (j.familles || []).forEach(function (f) {
      var e = evaluer(f.si || "", faits);
      if (!f.si) e = true;
      var memeVoie = !f.voie || f.voie === r.voie;
      if (e === true && memeVoie) r.entree = f;
      else if (e === true) r.autres.push(f);
      else if (e === null) r.possibles.push(f);
    });
    if (r.entree) {
      r.etat = r.entree.etat;
      r.mesure = r.entree;
    } else {
      var ref = familleDe(j.machine);
      r.ecart = ref != null && ref !== mac.famille;
    }
    return r;
  }

  function pastille(etat) {
    var p = el("span", "pastille etat-" + etat, T.etats[etat]);
    p.title = T.explications[etat];
    return p;
  }

  function lien(href, texte) {
    var a = el("a", null, texte);
    a.href = href;
    a.rel = "noopener";
    return a;
  }

  function ligne(dl, terme, valeur) {
    if (!valeur) return;
    dl.appendChild(el("dt", null, terme));
    var dd = el("dd");
    if (typeof valeur === "string") dd.textContent = valeur; else dd.appendChild(valeur);
    dl.appendChild(dd);
  }

  function mesure(m) {
    var bouts = [];
    if (m.fps_menu) bouts.push(T.menu + " " + m.fps_menu + " " + T.ips);
    if (m.fps_jeu) bouts.push(T.jeu + " " + m.fps_jeu + " " + T.ips);
    if (m.machine) bouts.push(T.sur_machine + " " + m.machine);
    if (m.cidre) bouts.push(T.cidre_version + " " + m.cidre);
    if (m.date) bouts.push(m.date);
    return bouts.join(" · ");
  }

  function notes(texte) {
    var p = el("p", "notes", texte);
    if (en) p.lang = "fr";
    return p;
  }

  function carte(j) {
    var s = surMac(j);
    var faits = faitsDe(mac);
    var li = el("li", "jeu origine-" + j.o);
    var tete = el("div", "tete");
    var titre = el("h3");
    titre.appendChild(lien("https://store.steampowered.com/app/" + j.id + "/", j.nom));
    tete.appendChild(titre);
    tete.appendChild(el("span", "appid", String(j.id)));
    li.appendChild(tete);

    var marques = el("div", "marques");
    marques.appendChild(pastille(s.etat));
    marques.appendChild(el("span", "origine", T.origines[j.o]));
    if (s.voie) marques.appendChild(el("span", "voie", VOIES[s.voie] || s.voie));
    if (j.protondb) {
      // une note importee : pas de Mac derriere, on le dit sur la pastille meme
      var p = el("span", "palier importe palier-" + j.protondb, "ProtonDB " + T.paliers[j.protondb] + " · " + T.linux_court);
      p.title = T.linux_titre;
      marques.appendChild(p);
    }
    li.appendChild(marques);

    // d'ou vient l'etat affiche, et s'il vaut pour le Mac choisi
    if (j.o === "t" && s.mesure.machine) {
      var ou = el("p", "provenance-etat" + (s.ecart ? " ecart" : ""));
      var phrase = T.mesure_sur(s.mesure.machine);
      if (s.entree) phrase += " (" + T.pour_entree(s.entree.nom) + ")";
      var ailleurs = s.autres.length + s.possibles.length > 0;
      ou.textContent = phrase + (s.ecart ? " — " + (ailleurs ? T.voir_dessous : T.pas_essaye)(mac.nom) : "");
      li.appendChild(ou);
    }

    var details = el("dl", "details");
    ligne(details, T.api, APIS[j.api] || j.api);
    ligne(details, T.moteur, MOTEURS[j.moteur] || j.moteur);
    ligne(details, T.anticheat, ANTICHEATS[j.anticheat] || j.anticheat);
    // la machine est dite juste au-dessus pour un jeu essaye
    ligne(details, T.mesure, mesure(j.o === "t" ? Object.assign({}, s.mesure, { machine: null }) : s.mesure));
    if (j.protondb) {
      var lp = lien("https://www.protondb.com/app/" + j.id, T.paliers[j.protondb]);
      var pdb = el("span");
      pdb.appendChild(lp);
      if (j.protondb_rapports) pdb.appendChild(document.createTextNode(" · " + T.rapports(j.protondb_rapports)));
      ligne(details, T.linux, pdb);
    }
    if (j.agw) {
      var agw = el("span");
      var bouts = [];
      if (j.agw.crossover) bouts.push(T.crossover + " " + T.agw[j.agw.crossover]);
      if (j.agw.wine) bouts.push(T.wine + " " + T.agw[j.agw.wine]);
      if (j.agw_url) agw.appendChild(lien(j.agw_url, bouts.join(" · "))); else agw.textContent = bouts.join(" · ");
      agw.appendChild(el("span", "inconnu", " · " + T.mac_inconnu));
      ligne(details, "AppleGamingWiki", agw);
    }
    if (details.childNodes.length) li.appendChild(details);
    if (s.mesure.notes) li.appendChild(notes(s.mesure.notes));

    // les autres voies que ce Mac sait prendre, et ce qui depend de ce qu'on ne sait pas
    if (s.autres.length) li.appendChild(entrees(T.autres_voies, s.autres, faits, false));
    if (s.possibles.length) li.appendChild(entrees(T.selon, s.possibles, faits, true));
    if (j.variantes) li.appendChild(reglages(j.variantes, faits));

    if (j.familles) {
      var bloc = el("details", "familles");
      bloc.appendChild(el("summary", null, T.familles + " (" + j.familles.length + ")"));
      var ul = el("ul");
      j.familles.forEach(function (f) {
        var fl = el("li");
        var t = el("div", "marques");
        t.appendChild(el("b", null, f.nom));
        t.appendChild(pastille(f.etat));
        if (mac && f === s.entree) t.appendChild(el("span", "ici", T.votre_mac));
        if (f.voie) t.appendChild(el("span", "voie", VOIES[f.voie] || f.voie));
        fl.appendChild(t);
        var d = el("dl", "details");
        ligne(d, T.mesure, mesure(f));
        if (f.options && f.etat !== "ko") {
          var c = el("code", null, f.options);
          ligne(d, T.options, c);
        }
        if (d.childNodes.length) fl.appendChild(d);
        if (f.notes) fl.appendChild(notes(f.notes));
        ul.appendChild(fl);
      });
      bloc.appendChild(ul);
      li.appendChild(bloc);
    }
    if (j.rapports) li.appendChild(rapports(j.rapports));
    return li;
  }

  function entrees(titre, liste, faits, avecCondition) {
    var bloc = el("div", "sur-mac");
    bloc.appendChild(el("h4", null, titre));
    liste.forEach(function (f) {
      var t = el("div", "marques");
      t.appendChild(pastille(f.etat));
      if (f.voie) t.appendChild(el("span", "voie", VOIES[f.voie] || f.voie));
      if (avecCondition) t.appendChild(el("span", "condition", f.nom + " · " + T.si + " " + condition(f.si, faits)));
      if (f.options && f.etat !== "ko") t.appendChild(el("code", null, f.options));
      bloc.appendChild(t);
      var m = mesure(f);
      if (m) bloc.appendChild(el("p", "mesure", m));
    });
    return bloc;
  }

  // Les blocs [[machine]] : ce que Cidre regle autrement sur certaines machines.
  function reglages(variantes, faits) {
    var choisis = variantes.map(function (v) { return { v: v, e: evaluer(v.si, faits) }; })
      .filter(function (x) { return !mac || x.e !== false; });
    var bloc = el(mac ? "div" : "details", "sur-mac variantes");
    if (!choisis.length) return document.createDocumentFragment();
    var titre = (mac ? T.reglages_mac : T.reglages_selon) + " (" + choisis.length + ")";
    bloc.appendChild(el(mac ? "h4" : "summary", null, titre));
    choisis.forEach(function (x) {
      var d = el("dl", "details");
      var cond = condition(x.v.si, faits);
      if (!mac || x.e === null) ligne(d, T.selon, cond ? T.si + " " + cond : "");
      if (x.v.options) ligne(d, T.lancement, el("code", null, x.v.options));
      (x.v.reglages || []).forEach(function (r) {
        var c = el("span");
        c.appendChild(document.createTextNode(r.fichier + " : "));
        c.appendChild(el("code", null, r.valeurs));
        ligne(d, T.jeu_reglages, c);
      });
      bloc.appendChild(d);
    });
    return bloc;
  }

  function rapports(liste) {
    var bloc = el("details", "familles rapports");
    bloc.appendChild(el("summary", null, T.rapports_titre + " (" + liste.length + ")"));
    var ul = el("ul");
    liste.forEach(function (r) {
      var fl = el("li");
      var t = el("div", "marques");
      t.appendChild(el("b", null, r.machine || "?"));
      t.appendChild(pastille(r.etat));
      if (r.voie) t.appendChild(el("span", "voie", VOIES[r.voie] || r.voie));
      var f = r.famille || familleDe(r.machine);
      t.appendChild(el("span", "condition", f ? famille(f) : T.sans_famille));
      if (mac && f === mac.famille) t.appendChild(el("span", "ici", T.meme_famille));
      fl.appendChild(t);
      var bouts = [mesure({ fps_menu: r.fps_menu, fps_jeu: r.fps_jeu, cidre: r.cidre, date: r.date })];
      if (r.macos_version) bouts.unshift("macOS " + r.macos_version);
      if (r.modele) bouts.unshift(r.modele);
      var p = el("p", "mesure", bouts.filter(Boolean).join(" · "));
      if (r.incident) { p.appendChild(document.createTextNode(" · ")); p.appendChild(lien(r.incident, T.incident)); }
      fl.appendChild(p);
      if (r.notes) fl.appendChild(notes(r.notes));
      ul.appendChild(fl);
    });
    bloc.appendChild(ul);
    return bloc;
  }

  // l'etat de chaque jeu sur le Mac choisi, puis l'ordre : les jeux essayes
  // d'abord, du meilleur etat au pire ; puis les fiches de Cidre, puis le
  // catalogue ; dans chaque groupe, les plus rapportes sur ProtonDB d'abord
  function classer() {
    tous.forEach(function (j) { j.ici = surMac(j).etat; });
    tous.sort(function (a, b) {
      return RANG_ORIGINE[a.o] - RANG_ORIGINE[b.o] ||
        RANG_ETAT[a.ici] - RANG_ETAT[b.ici] ||
        (b.protondb_rapports || 0) - (a.protondb_rapports || 0) ||
        a.nom.localeCompare(b.nom);
    });
  }

  function choisirMac(id, detecte) {
    mac = null;
    MACS.forEach(function (m) { if (m.id === id) mac = m; });
    macDetecte = !!(mac && detecte);
    choixMac.value = mac ? mac.id : "";
    noteMac.textContent = (mac ? T.pour_mac(mac) + (macDetecte ? " (" + T.detecte + ")" : "") : T.pour_tous) + " " + T.sans_machine;
  }

  // Chrome et Firefox nomment la puce dans le moteur de rendu WebGL
  // (« ANGLE Metal Renderer: Apple M1 Max ») ; Safari ne dit que « Apple GPU ».
  function deviner() {
    try {
      var gl = document.createElement("canvas").getContext("webgl");
      var ext = gl && gl.getExtension("WEBGL_debug_renderer_info");
      var nom = ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : "";
      var m = /Apple (M[0-9]+)(?: (Pro|Max|Ultra))?/.exec(nom || "");
      return m ? (m[1] + (m[2] ? "-" + m[2] : "")).toLowerCase() : "";
    } catch (e) { return ""; }
  }

  function appliquer() {
    var q = plier(filtre.q);
    var chiffres = /^[0-9]+$/.test(q);
    trouves = tous.filter(function (j) {
      if (filtre.etat && j.ici !== filtre.etat) return false;
      if (filtre.origine && j.o !== filtre.origine && !(filtre.origine === "d" && j.o === "t")) return false;
      if (!q) return true;
      if (chiffres && String(j.id).indexOf(q) === 0) return true;
      return j.cle.indexOf(q) !== -1;
    });
    liste.textContent = "";
    montres = 0;
    afficherSuite();
    compte.textContent = trouves.length === tous.length ? T.jeux(tous.length) : T.sur(trouves.length, tous.length);
    if (!trouves.length) liste.appendChild(el("li", "vide", T.aucun));
    retenir();
  }

  function afficherSuite() {
    var fin = Math.min(trouves.length, montres + PAGE);
    var morceau = document.createDocumentFragment();
    for (var i = montres; i < fin; i++) morceau.appendChild(carte(trouves[i]));
    liste.appendChild(morceau);
    montres = fin;
    var reste = trouves.length - montres;
    suite.hidden = reste <= 0;
    if (reste > 0) suite.textContent = T.plus(Math.min(PAGE, reste));
  }

  // Les filtres vivent dans l'adresse (?q=peak&etat=or) : un lien les garde.
  function retenir() {
    var p = new URLSearchParams();
    if (filtre.q) p.set("q", filtre.q);
    if (filtre.etat) p.set("etat", filtre.etat);
    if (filtre.origine) p.set("origine", filtre.origine);
    if (mac && !macDetecte) p.set("mac", mac.id);
    var s = p.toString();
    try { history.replaceState(null, "", s ? "?" + s : location.pathname); } catch (e) {}
    // l'autre langue garde la meme recherche
    langues.forEach(function (a) { a.href = a.dataset.base + (s ? "?" + s : ""); });
  }

  function relire() {
    var p = new URLSearchParams(location.search);
    filtre.q = p.get("q") || "";
    filtre.etat = RANG_ETAT.hasOwnProperty(p.get("etat")) ? p.get("etat") : "";
    filtre.origine = RANG_ORIGINE.hasOwnProperty(p.get("origine")) ? p.get("origine") : "";
    champ.value = filtre.q;
    choixOrigine.value = filtre.origine;
    marquerEtat();
  }

  function marquerEtat() {
    boutonsEtat.forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.dataset.etat === filtre.etat));
    });
  }

  var attente;
  champ.addEventListener("input", function () {
    clearTimeout(attente);
    attente = setTimeout(function () { filtre.q = champ.value.trim(); appliquer(); }, 120);
  });
  boutonsEtat.forEach(function (b) {
    b.addEventListener("click", function () {
      filtre.etat = b.dataset.etat;
      marquerEtat();
      appliquer();
    });
  });
  choixOrigine.addEventListener("change", function () { filtre.origine = choixOrigine.value; appliquer(); });

  var tousMac = el("option", null, T.tous_mac);
  tousMac.value = "";
  choixMac.appendChild(tousMac);
  [1, 2, 3, 4, 5].forEach(function (g) {
    var groupe = el("optgroup");
    groupe.label = "M" + g;
    MACS.forEach(function (m) {
      if (m.generation !== g) return;
      var o = el("option", null, m.nom);
      o.value = m.id;
      groupe.appendChild(o);
    });
    choixMac.appendChild(groupe);
  });
  var memorise = null;
  try { memorise = localStorage.getItem("verger-mon-mac"); } catch (e) {}
  // ?mac=m4 dans l'adresse (un lien partage) passe devant le choix memorise
  var demande = new URLSearchParams(location.search).get("mac");
  if (demande !== null) choisirMac(demande, false);
  else if (memorise !== null) choisirMac(memorise, false); else choisirMac(deviner(), true);
  choixMac.addEventListener("change", function () {
    try { localStorage.setItem("verger-mon-mac", choixMac.value); } catch (e) {}
    choisirMac(choixMac.value, false);
    if (tous.length) { classer(); appliquer(); }
  });
  suite.addEventListener("click", afficherSuite);

  relire();
  compte.textContent = T.chargement;
  fetch(racine.dataset.donnees)
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (d) {
      tous = d.jeux;
      tous.forEach(function (j) { j.cle = plier(j.nom); });
      classer();
      var c = d.entete.comptes;
      racine.querySelectorAll("[data-total]").forEach(function (e) {
        var n = e.dataset.total === "d" ? c.t + c.d : c[e.dataset.total];
        if (n != null) e.textContent = fmt(n);
      });
      var date = racine.querySelector("[data-date]");
      if (date && d.entete.donnees_du) date.textContent = d.entete.donnees_du;
      appliquer();
    })
    .catch(function () { compte.textContent = T.erreur; });
})();
