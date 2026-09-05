FROM ocaml/opam:debian-12-ocaml-5.2

USER root

# Install system dependencies required by Eliom and Ocsigen
RUN apt-get update && apt-get install -y \
    libgmp-dev \
    libssl-dev \
    libsqlite3-dev \
    sqlite3 \
    zlib1g-dev \
    pkg-config \
    m4 \
    && rm -rf /var/lib/apt/lists/*

USER opam

# Install Eliom (< 12), PPX RPC, Dune, and ocsipersist-sqlite
RUN opam update && \
    opam install -y \
    dune \
    "eliom<12" \
    ocsigen-ppx-rpc \
    ocsipersist-sqlite

ENV PATH="/home/opam/.opam/5.2/bin:${PATH}"

WORKDIR /home/opam/h42n42

# Copy repository sources with correct permissions
COPY --chown=opam:opam . /home/opam/h42n42

# Build the project
RUN eval $(opam env) && make build

EXPOSE 8080

# Default command to run the server
CMD ["bash", "-c", "eval $(opam env) && make run"]
