import FSFS

"""
    garonne_1875_config()

Reproduces the 23-24 June 1875 Garonne flood at Toulouse, the largest known
flood of the river ("l'Aigat de la Sant Joan"). The flood is driven by a
river source at the Garonne-Ariège confluence upstream of Toulouse; every
flood parameter below is anchored to the historical record. Quoted text is
from the sources listed at the end, tagged [S1]-[S5].

## Domain

bbox = (1.25, 43.42, 1.55, 43.80) covers the reach from Muret (where "le
pont suspendu a été arraché" [S1]), through Toulouse ("la crue atteint son
pic dans la nuit du 23 au 24 juin 1875" [S1]) down to Ondes, one of the
villages "entièrement réduits en ruine" [S1]. The Garonne-Ariège confluence
(Portet/Pinsaguel) lies inside the box, so one river source carries the
combined wave of both rivers ("la crue ne touche pas que la Garonne, mais
aussi ses affluents, particulièrement l'Ariège" [S1]).

## Resolution

spatial_resolution = 50 m keeps the ~400k-cell reach tractable for Torrent
and the ABM. temporal_resolution = 600 s over n_steps = 576 (4 days)
brackets the event: "le rythme de montée du niveau d'eau de la Garonne peut
atteindre 50 cm/h", "la durée habituelle entre le début et le maximum des
crues ... est de l'ordre de 18 à 48 heures à Toulouse" and "la durée de la
décrue est de l'ordre de 1 à 3 jours" [S2]. The asymmetric Gaussian
hydrograph written by write_river_sources peaks at 0.3 * n_steps = ~29 h,
inside the 18-48 h rise, and returns to the base flow within the 1-3 day
recession.

## Hydrograph

- peak_flux = 8000 m³/s, the conservative modern estimate. The 19th-century
  accounts report "au plus fort, le débit frôle les 18 000 m³/s" with
  "10 000 m³/s en moyenne du 23 juin midi au 24 juin à 6h du matin" [S3],
  while popular retellings give ">8 millions de litres par seconde, soit
  près de 42 fois son débit moyen" (8,000 m³/s) [S3]. 8,000 m³/s is the
  lower bound of that range; the higher figures are pre-rating-curve
  estimates and likely overestimates.
- base_flux = 200 m³/s, the mean flow of the Garonne (the 8,000 m³/s peak
  is "près de 42 fois son débit moyen" [S3]). The hydrograph is an
  asymmetric event on this base flow: a fast rise to the peak at
  0.3 * n_steps = ~29 h, inside the 18-48 h rise [S2], then a slow
  recession back to the base flow over the remaining 67 h, inside the
  1-3 day recession [S2].
- river_source at (43.522, 1.4135), in the Garonne channel just downstream
  of the Garonne-Ariège confluence, so the single source carries the
  combined flood wave (the channel cells at that latitude lie at
  lon 1.410-1.415 in the DEM, elevation ~142 m).

## DEM caveat

The Mapzen terrain tiles leave a one-cell-wide no-data seam at tile
boundaries (here at lon 1.406, which crosses the Garonne near Blagnac);
src/get_dem.jl now fills such holes (fill_dem_holes) before Torrent runs,
so the wave follows the channel instead of being hijacked by the seam.

## ABM limitations

- temporal_resolution = 600 s means an agent standing in >1.65 m of water
  accumulates death_time = 300 s within a single turn and dies immediately;
  with agents spawned only on cells that flood, the run's mortality is
  ~29% of the exposed population (7,661 of 26,242 agents), far above the
  476 historical deaths — the ABM models drowning only, and most 1875
  deaths came from the ~1,400 collapsing houses.
- The 58 m pool at the injection cell is a Torrent point-source artifact
  (8,000 m³/s into one 50 m cell), not a historical feature.

## Stage benchmark

"à l'échelle de mesure du Pont Neuf, le niveau d'eau atteint 8,32 m (le
niveau habituel est de 0,80 m)" [S1] and "[l]e pic de crue est atteint vers
minuit" [S2]. Caveat: the modern DEM includes the post-1952 dikes and an
incised bed, so "une crue d'intensité similaire à celle de juin 1875
atteindrait aujourd'hui 7,60 m à l'échelle du Pont-Neuf" [S2]; the simulated
extent therefore understates the 1875 flooding, which saw "le quartier de
Saint-Cyprien ... noyé sous plus de 3 mètres d'eau" [S1].

## Population

population = (iso3 = "FRA", year = 2020): WorldPop only covers 2000-2020,
so the 1875 city population (≈130,000: 124,852 in 1872 and 131,642 in 1876
[S5], with the faubourg Saint-Cyprien alone counting "plus de 30 000
habitants" [S3]) is approximated with present-day France and
population_ratio = 1. The historical benchmark: "209 victimes ... 25 000
personnes sont laissées sans logement" [S1] and "plus de 1 100 [S2] voire
1 400 [S1] habitations se sont effondrées" (1,140 [S4]) on the single city
of Toulouse; region-wide "476 victimes ... dont 209 dans la seule ville de
Toulouse" [S1].

## Rain

rain = nothing: the flood is fully carried by the injected hydrograph. The
trigger was "de très fortes pluies sur des sols gorgés d'eau" plus snowmelt
[S1], but no rainfall intensity is documented, and Torrent's precipitation
is in mm/h, so no anchored synthetic rain is used.

## Sources

[S1] Wikipédia, « Crue de la Garonne en 1875 »,
    https://fr.wikipedia.org/wiki/Crue_de_la_Garonne_en_1875
[S2] PAPI Toulouse Métropole, « Caractéristiques et historique des
    inondations » (source cited as [1] by S1),
    https://inondations-agglo-toulousaine.fr/caracteristiques-historique-inondations/
[S3] Rosalis, Bibliothèque de Toulouse, « Quand Toulouse fut submergée :
    l'inondation de 1875 »,
    https://rosalis.bibliotheque.toulouse.fr/rosalis/fr/content/quand-toulouse-fut-submergee-linondation-de-1875
[S4] Préfecture de Haute-Garonne, « Les 150 ans de la crue historique de la
    Garonne : les 23 et 24 juin 1875 »,
    https://www.haute-garonne.gouv.fr/index.php/Actions-de-l-Etat/Risques-naturels-technologiques-et-Cadre-de-vie/Connaissance-et-prevention-des-risques-naturels-et-technologiques2/Le-risque-en-Haute-Garonne-et-le-droit-a-l-information/Les-150-ans-de-la-crue-historique-de-la-Garonne-les-23-et-24-juin-1875
[S5] EHESS/Cassini census series for Toulouse (via Wikipédia, « Toulouse »,
    § Évolutions démographiques),
    http://cassini.ehess.fr/fr/html/fiche.php?select_resultat=37818
"""
function garonne_1875_config(; data_dir::String = FSFS.FSFS_DATA_DIR)::NamedTuple
    return (
        bbox=(1.25, 43.42, 1.55, 43.80),
        spatial_resolution=50.0,
        dem_zoom_level=12,
        temporal_resolution=600.0,
        n_steps=576,
        flood_threshold=0.01f0,
        speed=1.4,
        low_risk_perception=0.3,
        death_depth=1.65,
        death_time=300.0,
        max_crowd_density=6,
        entrance_ratio=0.1,
        penalty_walk_in_water=10,
        penalty_per_elevation=10,
        vision_range=100.0,
        population=(iso3="FRA", year=2020),
        population_ratio=1,
        rescue_ratio=0.01,
        warning_compliance=0.9,
        warning_response_delay=60.0,
        n_sources=500,
        rivulet_thickness=0.1,
        rivulet_length=10,
        default_manning=0.018f0,
        manning=FSFS.DEFAULT_MANNING,
        data_dir=data_dir,
        outdir=joinpath(data_dir, "sim_out", "garonne_1875"),
        rain=nothing,
        river_source=(lat=43.522, lon=1.4135, peak_flux=8000.0, base_flux=200.0),
        dam_failure=nothing,
    )
end

function main()
    config = garonne_1875_config()
    rm(config.outdir; recursive=true, force=true)
    result = FSFS.simulate(; config)
    println("garonne_1875: ", result.metrics)
    return nothing
end

function sweep_peak_flux()
    config = merge(garonne_1875_config(), (seed = 1312,))
    values = collect(range(195.0, 8000.0; length = 10))
    return FSFS.sweep_parameter(
        config,
        (:river_source, :peak_flux),
        values;
        outdir_root = joinpath(config.outdir, "sweep"),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
