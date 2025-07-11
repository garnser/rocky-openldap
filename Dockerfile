# === Stage 1: Build OpenLDAP from source with OpenSSL ===
FROM rockylinux:9-minimal as builder

ENV OPENLDAP_VERSION=2.6.9

RUN microdnf -y install dnf
RUN dnf -y groupinstall "Development Tools" && \
    dnf -y install \
    libdb-devel \
    openssl-devel \
    cyrus-sasl-devel \
    libtool \
    make \
    wget \
    tar && \
    dnf clean all

WORKDIR /opt

RUN wget https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-${OPENLDAP_VERSION}.tgz && \
    tar -xvzf openldap-${OPENLDAP_VERSION}.tgz && \
    cd openldap-${OPENLDAP_VERSION} && \
    ./configure --with-tls=openssl && \
    make depend && \
    make -j$(nproc) && \
    make install

# === Stage 2: Runtime container ===
FROM rockylinux:9-minimal

# Create ldap user
RUN groupadd -r ldap && useradd -r -g ldap -d /var/lib/ldap -s /sbin/nologin ldap
RUN microdnf -y install gettext && microdnf clean all

# Copy built OpenLDAP binaries
COPY --from=builder /usr/local/ /usr/local/

# Create required runtime directories
RUN mkdir -p /etc/openldap/slapd.d /var/lib/ldap /etc/openldap/certs /tmp/templates && \
    chown -R ldap:ldap /etc/openldap /var/lib/ldap

ENV PATH="/usr/local/libexec:/usr/local/bin:/usr/local/sbin:$PATH"

COPY entrypoint.sh /entrypoint.sh
COPY templates/ /usr/local/etc/openldap/templates/
RUN chmod +x /entrypoint.sh

VOLUME ["/etc/openldap/slapd.d", "/var/lib/ldap", "/etc/openldap/certs"]

CMD ["/entrypoint.sh"]
