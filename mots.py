from pathlib import Path


def charger_mots(chemin: str | Path = "mots.txt") -> list[str]:
    """Charge un mot par ligne depuis un fichier texte."""
    fichier = Path(chemin)
    mots = [ligne.strip() for ligne in fichier.read_text(encoding="utf-8").splitlines()]
    mots = [mot for mot in mots if mot]

    if not mots:
        raise ValueError(f"Le fichier {fichier} ne contient aucun mot.")

    return mots


def ajouter_mot(mot: str, chemin: str | Path = "mots.txt") -> str:
    """Ajoute un mot dans le fichier s'il n'existe pas déjà."""
    mot = mot.strip()
    if not mot:
        raise ValueError("Le mot ne peut pas être vide.")

    fichier = Path(chemin)
    mots_existants = charger_mots(fichier) if fichier.exists() else []
    if mot in mots_existants:
        raise ValueError("Ce mot existe déjà dans la liste.")

    with fichier.open("a", encoding="utf-8") as flux:
        if mots_existants:
            flux.write("\n")
        flux.write(mot)

    return mot


def supprimer_mot(mot: str, chemin: str | Path = "mots.txt") -> str:
    """Supprime un mot en conservant assez d'entrées pour une grille 3x3."""
    mot = mot.strip()
    fichier = Path(chemin)
    mots_existants = charger_mots(fichier)

    if mot not in mots_existants:
        raise ValueError("Ce mot n'existe pas dans la liste.")
    if len(mots_existants) <= 9:
        raise ValueError("Il faut conserver au moins 9 mots pour créer une grille.")

    mots_existants.remove(mot)
    fichier.write_text("\n".join(mots_existants) + "\n", encoding="utf-8")
    return mot


if __name__ == "__main__":
    for mot in charger_mots():
        print(mot)
