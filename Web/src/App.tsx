import { HashRouter, Routes, Route } from 'react-router-dom';
import Home from './pages/Home';
import Linux from './pages/Linux';
import Android from './pages/Android';
import Faq from './pages/Faq';
import Windows from './pages/Windows';
import Docs from './pages/Docs';
import Developers from './pages/Developers';
import License from './pages/License';
import { ThemeProvider } from './lib/theme';
import { LangProvider } from './lib/i18n';

function App() {
  return (
    <ThemeProvider>
      <LangProvider>
        <HashRouter>
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/linux" element={<Linux />} />
            <Route path="/android" element={<Android />} />
            <Route path="/faq" element={<Faq />} />
            <Route path="/windows" element={<Windows />} />
            <Route path="/docs" element={<Docs />} />
            <Route path="/developers" element={<Developers />} />
            <Route path="/license" element={<License />} />
          </Routes>
        </HashRouter>
      </LangProvider>
    </ThemeProvider>
  );
}

export default App;
