// La liste de compatibilite des jeux : lit jeux.json (Scripts/compatibilite.py),
// filtre par recherche, etat et provenance, et l'affiche par pages de 60.
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
    sur: function (n, total) { return fmt(n) + " of " + fmt(total) + " games"; },
    plus: function (n) { return "Show " + fmt(n) + " more"; },
    aucun: "No game matches. Try another spelling, or the Steam appid.",
    chargement: "Loading the list…",
    erreur: "The list could not be loaded.",
    rendu: "Rendering", api: "Game API", moteur: "Engine", anticheat: "Anti-cheat",
    mesure: "Measured", menu: "menu", jeu: "in game", ips: "fps", sur_machine: "on",
    familles: "By Mac family", options: "Options",
    linux: "ProtonDB (Linux)", rapports: function (n) { return fmt(n) + " reports"; },
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
    sur: function (n, total) { return fmt(n) + " jeux sur " + fmt(total); },
    plus: function (n) { return "Afficher " + fmt(n) + " de plus"; },
    aucun: "Aucun jeu ne correspond. Essaie une autre orthographe, ou l'appid Steam.",
    chargement: "Chargement de la liste…",
    erreur: "La liste n'a pas pu être chargée.",
    rendu: "Rendu", api: "API du jeu", moteur: "Moteur", anticheat: "Anti-triche",
    mesure: "Mesuré", menu: "menu", jeu: "en jeu", ips: "i/s", sur_machine: "sur",
    familles: "Par famille de Mac", options: "Options",
    linux: "ProtonDB (Linux)", rapports: function (n) { return fmt(n) + " rapports"; },
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

  var champ = racine.querySelector("[data-recherche]");
  var boutonsEtat = racine.querySelectorAll("[data-etat]");
  var choixOrigine = racine.querySelector("[data-origine]");
  var compte = racine.querySelector("[data-compte]");
  var liste = racine.querySelector("[data-liste]");
  var suite = racine.querySelector("[data-suite]");

  var langues = Array.prototype.slice.call(document.querySelectorAll(".langues a:not([aria-current])"));
  langues.forEach(function (a) { a.dataset.base = a.getAttribute("href"); });

  var tous = [];
  var trouves = [];
  var montres = 0;
  var filtre = { q: "", etat: "", origine: "" };

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
    var li = el("li", "jeu origine-" + j.o);
    var tete = el("div", "tete");
    var titre = el("h3");
    titre.appendChild(lien("https://store.steampowered.com/app/" + j.id + "/", j.nom));
    tete.appendChild(titre);
    tete.appendChild(el("span", "appid", String(j.id)));
    li.appendChild(tete);

    var marques = el("div", "marques");
    marques.appendChild(pastille(j.etat));
    marques.appendChild(el("span", "origine", T.origines[j.o]));
    if (j.voie) marques.appendChild(el("span", "voie", VOIES[j.voie] || j.voie));
    if (j.protondb) {
      var p = el("span", "palier palier-" + j.protondb, "ProtonDB " + T.paliers[j.protondb]);
      p.title = T.linux;
      marques.appendChild(p);
    }
    li.appendChild(marques);

    var details = el("dl", "details");
    ligne(details, T.api, APIS[j.api] || j.api);
    ligne(details, T.moteur, MOTEURS[j.moteur] || j.moteur);
    ligne(details, T.anticheat, ANTICHEATS[j.anticheat] || j.anticheat);
    ligne(details, T.mesure, mesure(j));
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
      ligne(details, "AppleGamingWiki", agw);
    }
    if (details.childNodes.length) li.appendChild(details);
    if (j.notes) li.appendChild(notes(j.notes));

    if (j.familles) {
      var bloc = el("details", "familles");
      bloc.appendChild(el("summary", null, T.familles + " (" + j.familles.length + ")"));
      var ul = el("ul");
      j.familles.forEach(function (f) {
        var fl = el("li");
        var t = el("div", "marques");
        t.appendChild(el("b", null, f.nom));
        t.appendChild(pastille(f.etat));
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
    return li;
  }

  function appliquer() {
    var q = plier(filtre.q);
    var chiffres = /^[0-9]+$/.test(q);
    trouves = tous.filter(function (j) {
      if (filtre.etat && j.etat !== filtre.etat) return false;
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
  suite.addEventListener("click", afficherSuite);

  relire();
  compte.textContent = T.chargement;
  fetch(racine.dataset.donnees)
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (d) {
      tous = d.jeux;
      tous.forEach(function (j) { j.cle = plier(j.nom); });
      // les jeux essayes d'abord, du meilleur etat au pire ; puis les fiches de Cidre,
      // puis le catalogue ; dans chaque groupe, les plus rapportes sur ProtonDB d'abord
      tous.sort(function (a, b) {
        return RANG_ORIGINE[a.o] - RANG_ORIGINE[b.o] ||
          RANG_ETAT[a.etat] - RANG_ETAT[b.etat] ||
          (b.protondb_rapports || 0) - (a.protondb_rapports || 0) ||
          a.nom.localeCompare(b.nom);
      });
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
