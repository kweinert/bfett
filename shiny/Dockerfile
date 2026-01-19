# Base image for our image
FROM ixpantia/faucet:r4.4

# Install the packages we need
RUN Rscript -e "install.packages(c('shiny', 'bslib'))"

# Copy the file app.R from our computer to the image
COPY app.R app.R
