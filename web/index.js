var app = new Vue({
  el: "#app",
  data: {
    loading: false,
    downloadRequestInFlight: false,
    statusPollTimer: null,
    preference: {
      showTranslation: true,
      commitWordWithSpace: true,
      enableNextWordPrediction: true,
      modelTier: 0
    },
    modelStatus: {
      isModelLoaded: false,
      currentTier: 0,
      smallModelAvailable: false,
      mediumModelAvailable: false,
      largeModelAvailable: false,
      xlargeModelAvailable: false,
      isDownloading: false,
      downloadProgress: 0,
      downloadingTier: 0,
      downloadStatus: "",
      modelDirectory: ""
    }
  },
  methods: {
    tierName(tier) {
      var names = { 0: "Small", 1: "Medium", 2: "Large", 3: "XLarge (Qwen2.5-3B)" };
      return names[tier] || "Unknown";
    },
    isTierAvailable(tier) {
      var keys = ["smallModelAvailable", "mediumModelAvailable", "largeModelAvailable", "xlargeModelAvailable"];
      return !!this.modelStatus[keys[tier]];
    },
    isDownloadingTier(tier) {
      return this.modelStatus.isDownloading && this.modelStatus.downloadingTier === tier;
    },
    downloadButtonLabel(tier) {
      if (this.isDownloadingTier(tier)) {
        return "Downloading...";
      }
      if (this.isTierAvailable(tier)) {
        return "Downloaded";
      }
      return "Download " + this.tierName(tier);
    },
    startStatusPolling() {
      if (this.statusPollTimer) {
        return;
      }
      this.statusPollTimer = window.setInterval(() => {
        this.getModelStatus();
      }, 1500);
    },
    stopStatusPolling() {
      if (!this.statusPollTimer) {
        return;
      }
      window.clearInterval(this.statusPollTimer);
      this.statusPollTimer = null;
    },
    getPreference() {
      fetch("http://localhost:62720/preference")
        .then(function(res) {
          return res.json();
        })
        .then(preference => {
          this.preference = preference;
        });
    },
    getModelStatus() {
      fetch("http://localhost:62720/model-status")
        .then(function(res) {
          return res.json();
        })
        .then(status => {
          this.modelStatus = status;
          if (status.isDownloading) {
            this.startStatusPolling();
          } else {
            this.stopStatusPolling();
          }
        })
        .catch(err => {
          console.log("Failed to get model status:", err);
        });
    },
    updatePreference() {
      this.loading = true;
      fetch("http://localhost:62720/preference", {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        body: JSON.stringify(this.preference)
      })
        .then(function(res) {
          return res.json();
        })
        .then(preference => {
          this.loading = false;
          // Refresh model status after saving
          this.getModelStatus();
        })
        .catch(err => {
          this.loading = false;
          console.log("Failed to update preference:", err);
        });
    },
    downloadModel(tier) {
      this.downloadRequestInFlight = true;
      fetch("http://localhost:62720/download-model", {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ tier: tier })
      })
        .then(function(res) {
          return res.json();
        })
        .then(status => {
          this.downloadRequestInFlight = false;
          this.modelStatus = status;
          if (status.isDownloading) {
            this.startStatusPolling();
          } else {
            this.stopStatusPolling();
          }
        })
        .catch(err => {
          this.downloadRequestInFlight = false;
          console.log("Failed to start model download:", err);
        });
    }
  }
});

app.getPreference();
app.getModelStatus();
