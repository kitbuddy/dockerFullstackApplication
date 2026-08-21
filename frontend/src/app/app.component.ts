import { Component } from '@angular/core';

@Component({
  selector: 'app-root',
  standalone: true,
  templateUrl: './app.component.html'
})
export class AppComponent {
  title = 'Angular + Spring Boot';
  message = 'Loading...';

  async ngOnInit() {
    await this.callBackend();
  }

  async callBackend() {
    const apiUrl = 'http://localhost:8080/api/hello';

    try {
      const res = await fetch(apiUrl, {
        method: 'GET',
        headers: {
          'Accept': 'application/json'
        }
      });

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}: ${res.statusText}`);
      }

      const data = await res.json();
      this.message = data.message || JSON.stringify(data);
    } catch (error) {
      this.message = 'Error calling backend: ' + (error instanceof Error ? error.message : String(error));
    }
  }
}
