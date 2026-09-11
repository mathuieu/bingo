import os

from flask import Flask, redirect, render_template, request, url_for

from grilles import GestionnaireGrilles
from mots import ajouter_mot, charger_mots, supprimer_mot


app = Flask(__name__)
gestionnaire = GestionnaireGrilles(
    charger_mots(),
    chemin_db=os.environ.get("DB_PATH", "grilles.db"),
)


@app.get("/")
def accueil():
    grille = None
    cases_cochees = []
    numero = None
    mode = request.args.get("mode", "")
    erreur = request.args.get("erreur")
    numero_saisi = request.args.get("numero", "").strip()

    if numero_saisi:
        try:
            numero = int(numero_saisi)
            grille, cases_cochees = gestionnaire.retrouver_grille_complete(numero)
        except ValueError:
            erreur = "Le numéro doit être un nombre entier."
        except KeyError as exception:
            erreur = str(exception.args[0])

    return render_template(
        "index.html",
        erreur=erreur,
        grille=grille,
        cases_cochees=cases_cochees,
        mode=mode,
        numero=numero,
        numero_saisi=numero_saisi,
    )

@app.post("/grilles")
def nouvelle_grille():
    numero_saisi = request.form.get("numero", "").strip()

    try:
        numero = int(numero_saisi) if numero_saisi else None
        numero, _ = gestionnaire.attribuer_grille(numero)
    except ValueError as exception:
        return redirect(url_for("accueil", erreur=str(exception), mode="creation"))

    return redirect(url_for("accueil", numero=numero))


@app.post("/grilles/<int:numero>/cases")
def enregistrer_cases(numero: int):
    donnees = request.get_json(silent=True) or {}
    cases_cochees = donnees.get("cases")

    if not isinstance(cases_cochees, list) or not all(
        isinstance(case, bool) for case in cases_cochees
    ):
        return {"erreur": "L'état des cases est invalide."}, 400

    try:
        grille, _ = gestionnaire.retrouver_grille_complete(numero)
        nombre_cases = sum(len(ligne) for ligne in grille)
        if len(cases_cochees) != nombre_cases:
            return {"erreur": "Le nombre de cases est invalide."}, 400
        gestionnaire.enregistrer_cases(numero, cases_cochees)
    except KeyError as exception:
        return {"erreur": str(exception.args[0])}, 404

    return {"ok": True}


@app.get("/admin")
def administration():
    return render_template(
        "admin.html",
        erreur=request.args.get("erreur"),
        grilles=gestionnaire.lister_grilles(),
        message=request.args.get("message"),
        mots=charger_mots(),
    )


@app.post("/admin/mots")
def administrer_mots():
    try:
        mot = ajouter_mot(request.form.get("mot", ""))
        gestionnaire.mots = charger_mots()
    except ValueError as exception:
        return redirect(url_for("administration", erreur=str(exception)))

    return redirect(url_for("administration", message=f"Mot ajouté : {mot}"))


@app.post("/admin/mots/supprimer")
def supprimer_mot_admin():
    try:
        mot = supprimer_mot(request.form.get("mot", ""))
        gestionnaire.mots = charger_mots()
    except ValueError as exception:
        return redirect(url_for("administration", erreur=str(exception)))

    return redirect(url_for("administration", message=f"Mot supprimé : {mot}"))


@app.post("/admin/reinitialiser")
def reinitialiser_grilles():
    gestionnaire.reinitialiser()
    return redirect(url_for("administration", message="Toutes les grilles ont été réinitialisées."))


if __name__ == "__main__":
    app.run(
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "5000")),
        debug=os.environ.get("FLASK_DEBUG", "0") == "1",
    )
