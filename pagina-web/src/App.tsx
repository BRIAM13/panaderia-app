import { Route, Routes } from "react-router-dom";
import { HomePage } from "./pages/HomePage";
import { CuentaPage } from "./pages/CuentaPage";

function App() {
  return (
    <Routes>
      <Route path="/" element={<HomePage />} />
      <Route path="/cuenta" element={<CuentaPage />} />
    </Routes>
  );
}

export default App;
