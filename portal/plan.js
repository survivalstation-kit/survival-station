// The family emergency plan's texts, fields and printable version, shared by plan.html and print.html.
// The plan itself is kept in the browser (localStorage 'family-plan') and, locked, in the kit's private folder.
const FAMILY_PLAN = (() => {
  const TXT = {
    en: {
      title: 'Family emergency plan',
      lede: 'Fill it in now, while things are calm. It is kept in this browser as you type. Print it for the go-bag and the fridge door, and save a locked copy on the kit.',
      print: '🖨 Print', download: '⬇ Download a copy', clear: '🗑 Clear on this device', 'clear.ask': 'Clear the plan on this device? Printed and saved copies are not affected.',
      'kit.intro': 'On the computer running the kit: save the plan on the stick, locked with a password (the same one as PRIVATE-DOCS.bat). Phones on the hotspot can\'t see it.',
      'kit.pw': 'Password (6+ characters)', 'kit.save': '🔒 Save to the kit, locked', 'kit.load': '🔓 Load from the kit',
      'kit.saved': 'Saved on the kit, locked. Write the password down somewhere safe.', 'kit.loaded': 'Loaded from the kit.', 'kit.none': 'No plan saved on this kit yet.',
      'kit.noplan': 'Nothing to save yet.', saved: 'Kept in this browser', updated: 'Updated',
      'err.wrong': 'Wrong password (it must be the one the kit\'s private documents were locked with).', 'err.short': 'Choose a password of at least 6 characters.',
      'err.helper': 'Couldn\'t reach the kit helper: close the kit and start it again.',
      'people.h': 'People in the household', 'people.add': '+ Add a person',
      name: 'Name', born: 'Date of birth', blood: 'Blood type', phone: 'Phone', allergies: 'Allergies', meds: 'Medicines and doses', conditions: 'Health conditions, devices, needs',
      'contacts.h': 'Emergency contacts', 'contacts.note': 'Include one person far away: after a disaster, long-distance calls and texts often get through when local ones don\'t.', 'contacts.add': '+ Add a contact',
      relation: 'Relation', where: 'Where they live',
      'places.h': 'Where to meet', 'places.home': 'Near home (e.g. the big tree across the street)', 'places.area': 'In the neighbourhood, if you can\'t get home', 'places.town': 'Out of town, if you have to leave',
      'medical.h': 'Medical', doctor: 'Doctor and phone', pharmacy: 'Pharmacy', insurance: 'Health insurance / SUS card numbers',
      'docs.h': 'Documents', 'docs.note': 'ID, passport, driver\'s licence, tax numbers, bank and insurance policies. Keep scans in the kit\'s private folder, locked.',
      'home.h': 'Home', shutoffs: 'Where to turn off gas, water and electricity', pets: 'Pets (names, food, medicines, vet)', 'home.other': 'Other (spare key, generator, radio channel)',
      'notes.h': 'Notes', notes: 'Anything else: school pick-up plans, radio channel and times (3-3-3), who checks on elderly neighbours',
      'print.h': 'Family emergency plan', 'print.updated': 'Updated',
    },
    'pt-BR': {
      title: 'Plano de emergência da família',
      lede: 'Preencha agora, com calma. Fica guardado neste navegador enquanto você digita. Imprima para a mochila de emergência e a porta da geladeira, e salve uma cópia trancada no kit.',
      print: '🖨 Imprimir', download: '⬇ Baixar uma cópia', clear: '🗑 Apagar neste aparelho', 'clear.ask': 'Apagar o plano neste aparelho? Cópias impressas e salvas não mudam.',
      'kit.intro': 'No computador que roda o kit: salve o plano no pendrive, trancado com senha (a mesma do PRIVATE-DOCS.bat). Celulares no roteador não conseguem vê-lo.',
      'kit.pw': 'Senha (6+ caracteres)', 'kit.save': '🔒 Salvar no kit, trancado', 'kit.load': '🔓 Carregar do kit',
      'kit.saved': 'Salvo no kit, trancado. Anote a senha num lugar seguro.', 'kit.loaded': 'Carregado do kit.', 'kit.none': 'Ainda não há plano salvo neste kit.',
      'kit.noplan': 'Ainda não há nada para salvar.', saved: 'Guardado neste navegador', updated: 'Atualizado',
      'err.wrong': 'Senha errada (tem que ser a mesma com que os documentos privados do kit foram trancados).', 'err.short': 'Escolha uma senha de pelo menos 6 caracteres.',
      'err.helper': 'Não deu para falar com o ajudante do kit: feche o kit e inicie de novo.',
      'people.h': 'Pessoas da casa', 'people.add': '+ Adicionar pessoa',
      name: 'Nome', born: 'Data de nascimento', blood: 'Tipo sanguíneo', phone: 'Telefone', allergies: 'Alergias', meds: 'Remédios e doses', conditions: 'Doenças, aparelhos, necessidades',
      'contacts.h': 'Contatos de emergência', 'contacts.note': 'Inclua uma pessoa longe daqui: depois de um desastre, ligações e mensagens para longe muitas vezes passam quando as locais não passam.', 'contacts.add': '+ Adicionar contato',
      relation: 'Parentesco', where: 'Onde mora',
      'places.h': 'Onde se encontrar', 'places.home': 'Perto de casa (ex.: a árvore grande do outro lado da rua)', 'places.area': 'No bairro, se não der para voltar para casa', 'places.town': 'Fora da cidade, se precisar sair',
      'medical.h': 'Saúde', doctor: 'Médico e telefone', pharmacy: 'Farmácia', insurance: 'Plano de saúde / cartão do SUS',
      'docs.h': 'Documentos', 'docs.note': 'RG, CPF, passaporte, CNH, título de eleitor, banco e seguros. Guarde as cópias escaneadas na pasta privada do kit, trancadas.',
      'home.h': 'Casa', shutoffs: 'Onde desligar gás, água e luz', pets: 'Animais (nomes, ração, remédios, veterinário)', 'home.other': 'Outros (chave reserva, gerador, canal de rádio)',
      'notes.h': 'Observações', notes: 'Outras coisas: quem busca as crianças na escola, canal e horários de rádio (3-3-3), quem vê os vizinhos idosos',
      'print.h': 'Plano de emergência da família', 'print.updated': 'Atualizado',
    },
  };
  const T = TXT[SURVIVAL.lang] || TXT.en;
  const tt = k => T[k] ?? TXT.en[k] ?? k;
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
  // ---- the plan: { people: [{...}], contacts: [{...}], fields: { key: text }, updated }
  const PERSON = ['name', 'born', 'blood', 'phone', 'allergies', 'meds', 'conditions'];
  const CONTACT = ['name', 'relation', 'phone', 'where'];
  const SECTIONS = [
    ['places.h', null, ['places.home', 'places.area', 'places.town']],
    ['medical.h', null, ['doctor', 'pharmacy', 'insurance']],
    ['docs.h', 'docs.note', ['docs']],
    ['home.h', null, ['shutoffs', 'pets', 'home.other']],
    ['notes.h', null, ['notes']],
  ];
  const LONG = new Set(['allergies', 'meds', 'conditions', 'docs', 'notes', 'pets', 'home.other', 'shutoffs', 'insurance']);
  // ---- the printable version (also what Download and the kit's locked copy hold): plain tables
  function printable(plan) {
    const out = el('div');
    out.append(el('h1', null, tt('print.h')));
    if (plan.updated) out.append(el('p', 'muted', `${tt('print.updated')}: ${new Date(plan.updated).toLocaleString(SURVIVAL.lang)}`));
    const table = (title, rows, keys) => {
      const filled = rows.filter(r => keys.some(k => r[k]));
      if (!filled.length) return;
      out.append(el('h2', null, tt(title)));
      const tb = el('table');
      const head = tb.insertRow(); keys.forEach(k => head.append(el('th', null, tt(k))));
      filled.forEach(r => { const tr = tb.insertRow(); keys.forEach(k => { tr.insertCell().textContent = r[k] || ''; }); });
      out.append(tb);
    };
    table('people.h', plan.people, PERSON);
    table('contacts.h', plan.contacts, CONTACT);
    for (const [title, , keys] of SECTIONS) {
      const filled = keys.filter(k => plan.fields[k]);
      if (!filled.length) continue;
      out.append(el('h2', null, tt(title)));
      const tb = el('table');
      filled.forEach(k => { const tr = tb.insertRow(); tr.append(el('th', null, tt(k === 'docs' ? 'docs.h' : k))); tr.insertCell().textContent = plan.fields[k]; });
      out.append(tb);
    }
    return out;
  }
  const load = () => { try { return JSON.parse(SURVIVAL.store('family-plan') || 'null'); } catch { return null; } };
  return { tt, PERSON, CONTACT, SECTIONS, LONG, printable, load };
})();
