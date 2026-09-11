import json
import random
import sqlite3
from collections.abc import Iterable
from contextlib import closing
from pathlib import Path


Grille = list[list[str]]


def generer_grille(mots: Iterable[str], taille: int = 3) -> Grille:
    """Génère une grille carrée aléatoire à partir des mots fournis."""
    if taille < 1:
        raise ValueError("La taille de la grille doit être positive.")

    mots_uniques = list(dict.fromkeys(mots))
    nombre_cases = taille * taille
    if len(mots_uniques) < nombre_cases:
        raise ValueError(
            f"Il faut au moins {nombre_cases} mots différents pour une grille {taille}x{taille}."
        )

    selection = random.sample(mots_uniques, nombre_cases)
    return [selection[index : index + taille] for index in range(0, nombre_cases, taille)]


class GestionnaireGrilles:
    """Attribue des grilles numérotées et permet de les retrouver."""

    def __init__(
        self,
        mots: Iterable[str],
        taille: int = 3,
        chemin_db: str | Path = "grilles.db",
    ) -> None:
        self.mots = list(mots)
        self.taille = taille
        self.chemin_db = Path(chemin_db)
        self._initialiser_base()

    def _initialiser_base(self) -> None:
        with closing(sqlite3.connect(self.chemin_db)) as connexion, connexion:
            connexion.execute(
                """
                CREATE TABLE IF NOT EXISTS grilles (
                    numero INTEGER PRIMARY KEY AUTOINCREMENT,
                    contenu TEXT NOT NULL,
                    cases_cochees TEXT NOT NULL DEFAULT '[]'
                )
                """
            )
            colonnes = {
                ligne[1]
                for ligne in connexion.execute("PRAGMA table_info(grilles)").fetchall()
            }
            if "cases_cochees" not in colonnes:
                connexion.execute(
                    "ALTER TABLE grilles ADD COLUMN cases_cochees TEXT NOT NULL DEFAULT '[]'"
                )

    def attribuer_grille(self, numero: int | None = None) -> tuple[int, Grille]:
        if numero is not None and numero < 1:
            raise ValueError("Le numéro de grille doit être positif.")

        grille = generer_grille(self.mots, self.taille)
        contenu = json.dumps(grille, ensure_ascii=False)

        try:
            with closing(sqlite3.connect(self.chemin_db)) as connexion, connexion:
                if numero is None:
                    resultat = connexion.execute(
                        "INSERT INTO grilles (contenu) VALUES (?)",
                        (contenu,),
                    )
                    numero = resultat.lastrowid
                else:
                    connexion.execute(
                        "INSERT INTO grilles (numero, contenu) VALUES (?, ?)",
                        (numero, contenu),
                    )
        except sqlite3.IntegrityError as erreur:
            raise ValueError(f"La grille n°{numero} existe déjà.") from erreur

        if numero is None:
            raise RuntimeError("La base de données n'a pas attribué de numéro.")

        return numero, grille

    def retrouver_grille(self, numero: int) -> Grille:
        with closing(sqlite3.connect(self.chemin_db)) as connexion:
            resultat = connexion.execute(
                "SELECT contenu FROM grilles WHERE numero = ?",
                (numero,),
            ).fetchone()

        if resultat is None:
            raise KeyError(f"Aucune grille ne correspond au numéro {numero}.")

        return json.loads(resultat[0])

    def retrouver_grille_complete(self, numero: int) -> tuple[Grille, list[bool]]:
        with closing(sqlite3.connect(self.chemin_db)) as connexion:
            resultat = connexion.execute(
                "SELECT contenu, cases_cochees FROM grilles WHERE numero = ?",
                (numero,),
            ).fetchone()

        if resultat is None:
            raise KeyError(f"Aucune grille ne correspond au numéro {numero}.")

        grille = json.loads(resultat[0])
        cases_cochees = json.loads(resultat[1])
        if len(cases_cochees) != sum(len(ligne) for ligne in grille):
            cases_cochees = [False] * sum(len(ligne) for ligne in grille)
        return grille, cases_cochees

    def enregistrer_cases(self, numero: int, cases_cochees: list[bool]) -> None:
        with closing(sqlite3.connect(self.chemin_db)) as connexion, connexion:
            resultat = connexion.execute(
                "UPDATE grilles SET cases_cochees = ? WHERE numero = ?",
                (json.dumps(cases_cochees), numero),
            )
            if resultat.rowcount == 0:
                raise KeyError(f"Aucune grille ne correspond au numéro {numero}.")

    def lister_grilles(self) -> list[tuple[int, Grille]]:
        with closing(sqlite3.connect(self.chemin_db)) as connexion:
            resultats = connexion.execute(
                "SELECT numero, contenu FROM grilles ORDER BY numero"
            ).fetchall()

        return [(numero, json.loads(contenu)) for numero, contenu in resultats]

    def compter_grilles(self) -> int:
        with closing(sqlite3.connect(self.chemin_db)) as connexion:
            resultat = connexion.execute("SELECT COUNT(*) FROM grilles").fetchone()

        if resultat is None:
            return 0
        return resultat[0]

    def reinitialiser(self) -> None:
        with closing(sqlite3.connect(self.chemin_db)) as connexion, connexion:
            connexion.execute("DELETE FROM grilles")
            connexion.execute("DELETE FROM sqlite_sequence WHERE name = 'grilles'")


def afficher_grille(numero: int, grille: Grille) -> None:
    print(f"Grille n°{numero}")
    for ligne in grille:
        print(" | ".join(ligne))


if __name__ == "__main__":
    from mots import charger_mots

    gestionnaire = GestionnaireGrilles(charger_mots())
    numero, grille = gestionnaire.attribuer_grille()
    afficher_grille(numero, grille)
    afficher_grille(numero, gestionnaire.retrouver_grille(numero))
